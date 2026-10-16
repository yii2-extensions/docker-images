#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "httpd.h"
#include "http_config.h"
#include "http_log.h"
#include "http_main.h"
#include "mod_log_config.h"
#include "util_mutex.h"
#include "apr_global_mutex.h"
#include "apr_file_io.h"

#include "json_log_escape.h"

#define JSON_MARKER "@yii2-json@"
#define JSON_MUTEX "yii2-json-log"
#define JSON_MUTEX_KEY "yii2-json-log-lock-v1"
static const char json_marker_value[] = JSON_MARKER;

module AP_MODULE_DECLARE_DATA yii2_log_json_module;
static ap_log_writer *next_writer;
static ap_log_writer *unbuffered_writer;
static ap_log_writer_init *unbuffered_init;
static int direct_files;
static apr_global_mutex_t *write_mutex;
static const char *mutex_file;

typedef struct {
    apr_global_mutex_t *mutex;
    const char *file;
} json_mutex_state;

/* Own the unbuffered APR handles through the public init hook; other writers keep their opaque handles. */
static void *json_file_init(apr_pool_t *p, server_rec *s, const char *name)
{
    apr_file_t *file;
    apr_status_t rv;
    const char *path;
    if (name[0] == '|') {
        piped_log *pipe = ap_open_piped_log(p, name + 1);
        return pipe ? ap_piped_log_write_fd(pipe) : NULL;
    }
    path = ap_server_root_relative(p, name);
    if (!path) {
        ap_log_error(APLOG_MARK, APLOG_ERR, APR_EBADPATH, s, "yii2 JSON log: invalid access log path %s", name);
        return NULL;
    }
    rv = apr_file_open(&file, path, APR_WRITE | APR_APPEND | APR_CREATE | APR_LARGEFILE, APR_OS_DEFAULT, p);
    if (rv != APR_SUCCESS) {
        ap_log_error(APLOG_MARK, APLOG_ERR, rv, s, "yii2 JSON log: cannot open access log %s", name);
        return NULL;
    }
    return file;
}

static const char *json_marker(request_rec *r, char *arg)
{
    /* CLF's %u represents an empty user as two raw quotes; JSON needs the actual empty value. */
    if (arg && strcmp(arg, "user") == 0) return ap_escape_logitem(r->pool, r->user ? r->user : "-");
    return json_marker_value;
}

static apr_status_t json_writer(request_rec *r, void *handle, const char **parts,
                                int *lengths, int count, apr_size_t length)
{
    char *input, *output, *cursor;
    unsigned char *scratch;
    const char *record;
    size_t encoded;
    int i, record_length, first;
    apr_status_t rv, unlock_rv;

    first = count > 0 && lengths[0] == (int)(sizeof(JSON_MARKER) - 1) && parts[0] == json_marker_value;
    if (!first && !direct_files) {
        return next_writer(r, handle, parts, lengths, count, length);
    }
    if (first) length -= sizeof(JSON_MARKER) - 1;
    /* The delegated writer accepts an int length per portion. Never truncate a record. */
    if (length > (INT_MAX - 1) / 6) return APR_ENOMEM;
    input = apr_palloc(r->pool, length + 1);
    cursor = input;
    for (i = first; i < count; ++i) {
        memcpy(cursor, parts[i], (size_t)lengths[i]);
        cursor += lengths[i];
    }
    *cursor = '\0';
    output = input;
    encoded = length;
    if (first) {
        scratch = apr_palloc(r->pool, length + 1);
        output = apr_palloc(r->pool, length * 6 + 1);
        encoded = yii2_json_record(input, length, scratch, output);
        if (encoded == SIZE_MAX) {
            ap_log_rerror(APLOG_MARK, APLOG_ERR, APR_EINVAL, r,
                            "yii2 JSON log: malformed string escape in marked LogFormat");
            return APR_EINVAL;
        }
    }
    record = output;
    record_length = (int)encoded;
    /* Serialize whole records across workers, including writes larger than PIPE_BUF to stdout or a pipe. */
    rv = apr_global_mutex_lock(write_mutex);
    if (rv != APR_SUCCESS) return rv;
    /* Complete short writes on our own unbuffered handles; do not cast another writer's opaque context. */
    if (direct_files) rv = apr_file_write_full((apr_file_t *)handle, record, encoded, NULL);
    else rv = next_writer(r, handle, &record, &record_length, 1, encoded);
    unlock_rv = apr_global_mutex_unlock(write_mutex);
    return rv != APR_SUCCESS ? rv : unlock_rv;
}

static int json_pre_config(apr_pool_t *p, apr_pool_t *plog, apr_pool_t *ptemp)
{
    APR_OPTIONAL_FN_TYPE(ap_register_log_handler) *register_handler;
    APR_OPTIONAL_FN_TYPE(ap_log_set_writer) *set_writer;
    APR_OPTIONAL_FN_TYPE(ap_log_set_writer_init) *set_init;
    (void)plog; (void)ptemp;
    register_handler = APR_RETRIEVE_OPTIONAL_FN(ap_register_log_handler);
    set_writer = APR_RETRIEVE_OPTIONAL_FN(ap_log_set_writer);
    set_init = APR_RETRIEVE_OPTIONAL_FN(ap_log_set_writer_init);
    if (!register_handler || !set_writer || !set_init) return HTTP_INTERNAL_SERVER_ERROR;
    unbuffered_writer = set_writer(NULL);
    set_writer(unbuffered_writer);
    unbuffered_init = set_init(NULL);
    set_init(unbuffered_init);
    if (!unbuffered_writer || !unbuffered_init) return HTTP_INTERNAL_SERVER_ERROR;
    register_handler(p, "J", json_marker, 0);
    return ap_mutex_register(p, JSON_MUTEX, NULL, APR_LOCK_DEFAULT, 0) == APR_SUCCESS
        ? OK : HTTP_INTERNAL_SERVER_ERROR;
}

static int json_check_config(apr_pool_t *p, apr_pool_t *plog, apr_pool_t *ptemp, server_rec *s)
{
    APR_OPTIONAL_FN_TYPE(ap_log_set_writer) *set_writer = APR_RETRIEVE_OPTIONAL_FN(ap_log_set_writer);
    APR_OPTIONAL_FN_TYPE(ap_log_set_writer_init) *set_init = APR_RETRIEVE_OPTIONAL_FN(ap_log_set_writer_init);
    ap_log_writer *previous;
    ap_log_writer_init *initialize;
    (void)p; (void)plog; (void)ptemp; (void)s;
    previous = set_writer(json_writer);
    if (previous == json_writer) return OK;
    next_writer = previous;
    initialize = set_init(NULL);
    set_init(initialize);
    direct_files = previous == unbuffered_writer && initialize == unbuffered_init;
    if (direct_files) set_init(json_file_init);
    return next_writer ? OK : HTTP_INTERNAL_SERVER_ERROR;
}

static int json_post_config(apr_pool_t *p, apr_pool_t *plog, apr_pool_t *ptemp, server_rec *s)
{
    apr_status_t rv;
    json_mutex_state *state = NULL;
    apr_pool_t *process_pool = s->process->pool;
    (void)plog; (void)ptemp;
    (void)p;
    /* Keep one lock for the parent lifetime: old and new workers must share it during a graceful restart. */
    apr_pool_userdata_get((void **)&state, JSON_MUTEX_KEY, process_pool);
    if (!state) {
        state = apr_pcalloc(process_pool, sizeof(*state));
        rv = ap_global_mutex_create(&state->mutex, &state->file, JSON_MUTEX, NULL, s, process_pool, 0);
        if (rv != APR_SUCCESS) return HTTP_INTERNAL_SERVER_ERROR;
        apr_pool_userdata_set(state, JSON_MUTEX_KEY, NULL, process_pool);
    }
    write_mutex = state->mutex;
    mutex_file = state->file;
    return OK;
}

static void json_child_init(apr_pool_t *p, server_rec *s)
{
    apr_status_t rv = apr_global_mutex_child_init(&write_mutex, mutex_file, p);
    if (rv != APR_SUCCESS) {
        ap_log_error(APLOG_MARK, APLOG_CRIT, rv, s, "yii2 JSON log: cannot initialize worker mutex");
        exit(APEXIT_CHILDFATAL);
    }
}

static void json_register_hooks(apr_pool_t *p)
{
    static const char *const predecessors[] = { "mod_log_config.c", NULL };
    (void)p;
    ap_hook_pre_config(json_pre_config, predecessors, NULL, APR_HOOK_REALLY_FIRST + 1);
    ap_hook_check_config(json_check_config, predecessors, NULL, APR_HOOK_LAST);
    ap_hook_post_config(json_post_config, NULL, NULL, APR_HOOK_LAST);
    ap_hook_child_init(json_child_init, NULL, NULL, APR_HOOK_MIDDLE);
}

AP_DECLARE_MODULE(yii2_log_json) = {
    STANDARD20_MODULE_STUFF,
    NULL, NULL, NULL, NULL, NULL,
    json_register_hooks,
    AP_MODULE_FLAG_NONE
};
