#ifndef YII2_JSON_LOG_ESCAPE_H
#define YII2_JSON_LOG_ESCAPE_H

#include <stddef.h>
#include <stdint.h>

static int yii2_json_hex(unsigned char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* Reject overlong encodings, surrogates, incomplete sequences and values above U+10FFFF. */
static size_t yii2_json_utf8(const unsigned char *s, size_t n)
{
    size_t width, i;
    if (s[0] >= 0xc2 && s[0] <= 0xdf) width = 2;
    else if (s[0] >= 0xe0 && s[0] <= 0xef) width = 3;
    else if (s[0] >= 0xf0 && s[0] <= 0xf4) width = 4;
    else return 0;
    if (n < width) return 0;
    for (i = 1; i < width; ++i) {
        if (s[i] < 0x80 || s[i] > 0xbf) return 0;
    }
    if ((s[0] == 0xe0 && s[1] < 0xa0) || (s[0] == 0xed && s[1] > 0x9f) ||
        (s[0] == 0xf0 && s[1] < 0x90) || (s[0] == 0xf4 && s[1] > 0x8f)) return 0;
    return width;
}

/* Convert Apache's escaped string bytes to JSON. Valid UTF-8 stays UTF-8; other bytes use \u00HH. */
static size_t yii2_json_string(const unsigned char *s, size_t n, char *out)
{
    static const char hex[] = "0123456789abcdef";
    size_t i = 0, j = 0, width, k;
    unsigned char c;
    while (i < n) {
        c = s[i];
        if (c >= 0x80 && (width = yii2_json_utf8(s + i, n - i)) != 0) {
            for (k = 0; k < width; ++k) out[j++] = (char)s[i++];
            continue;
        }
        ++i;
        if (c == '"' || c == '\\') {
            out[j++] = '\\';
            out[j++] = (char)c;
        }
        else if (c < 0x20 || c >= 0x7f) {
            out[j++] = '\\'; out[j++] = 'u'; out[j++] = '0'; out[j++] = '0';
            out[j++] = hex[c >> 4]; out[j++] = hex[c & 15];
        }
        else out[j++] = (char)c;
    }
    return j;
}

/*
 * The input is the fixed JSON LogFormat with C-escaped formatter values, not arbitrary JSON.
 * scratch needs n bytes; out needs 6*n+1 bytes. SIZE_MAX reports a malformed string escape.
 * Decode by string boundaries: a literal \\x41 must stay distinct from Apache's \x41.
 */
static size_t yii2_json_record(const char *input, size_t n, unsigned char *scratch, char *out)
{
    size_t i = 0, j = 0, used;
    int high, low, closed;
    unsigned char c;
    if (n == 0 || input[0] != '{') return SIZE_MAX;
    while (i < n) {
        c = (unsigned char)input[i++];
        if (c != '"') {
            if (c >= 0x80 || c == '\\' || (c < 0x20 && c != '\n' && c != '\r' && c != '\t')) return SIZE_MAX;
            out[j++] = (char)c;
            continue;
        }
        out[j++] = '"';
        used = 0;
        closed = 0;
        while (i < n) {
            c = (unsigned char)input[i++];
            if (c == '"') { closed = 1; break; }
            if (c == '\\') {
                if (i == n) return SIZE_MAX;
                c = (unsigned char)input[i++];
                switch (c) {
                    case '"': case '\\': break;
                    case 'b': c = '\b'; break;
                    case 'f': c = '\f'; break;
                    case 'n': c = '\n'; break;
                    case 'r': c = '\r'; break;
                    case 't': c = '\t'; break;
                    case 'v': c = '\v'; break;
                    case 'x':
                        if (n - i < 2) return SIZE_MAX;
                        high = yii2_json_hex((unsigned char)input[i]);
                        low = yii2_json_hex((unsigned char)input[i + 1]);
                        if (high < 0 || low < 0) return SIZE_MAX;
                        c = (unsigned char)((high << 4) | low);
                        i += 2;
                        break;
                    default: return SIZE_MAX;
                }
            }
            scratch[used++] = c;
        }
        if (!closed) return SIZE_MAX;
        j += yii2_json_string(scratch, used, out + j);
        out[j++] = '"';
    }
    out[j] = '\0';
    return j;
}

#endif
