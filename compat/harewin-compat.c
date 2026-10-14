/*
 * 最小Windowsホスト互換実装（コンパイラ専用）。
 * POSIX一般互換を保証するものではなく、harecの利用範囲だけを扱う。
 */
#include "harewin-compat.h"
#include <limits.h>
#include <stdint.h>
#include <string.h>

#ifdef _WIN32
char *harewin_optarg = NULL;
int harewin_optind = 1;
int harewin_optopt = 0;

int
harewin_getopt(int argc, char *const argv[], const char *options)
{
    /* harecのオプションは単一文字。-Dfoo / -D foo の両方を扱う。 */
    static const char *next = NULL;
    harewin_optarg = NULL;
    if (!next || !*next) {
        if (harewin_optind >= argc) return -1;
        const char *arg = argv[harewin_optind];
        if (!arg || arg[0] != '-' || arg[1] == '\0') return -1;
        if (strcmp(arg, "--") == 0) { ++harewin_optind; return -1; }
        next = arg + 1;
        ++harewin_optind;
    }
    char option = *next++;
    const char *match = strchr(options, option);
    if (!match || option == ':') {
        harewin_optopt = option;
        return '?';
    }
    if (match[1] == ':') {
        if (*next) {
            harewin_optarg = (char *)next;
        } else if (harewin_optind < argc) {
            harewin_optarg = argv[harewin_optind++];
        } else {
            harewin_optopt = option;
            next = NULL;
            return '?';
        }
        next = NULL;
    }
    return option;
}

FILE *
harewin_fmemopen(const void *buffer, size_t length, const char *mode)
{
    /* harecは読み取り専用("r")で呼び出す。実メモリFILEである必要はない。 */
    if (!mode || strcmp(mode, "r") != 0 || (length && !buffer)) {
        errno = EINVAL;
        return NULL;
    }
    FILE *stream = tmpfile();
    if (!stream) return NULL;
    if (length && fwrite(buffer, 1, length, stream) != length) {
        fclose(stream);
        return NULL;
    }
    if (fseek(stream, 0, SEEK_SET) != 0) {
        fclose(stream);
        return NULL;
    }
    return stream;
}

ssize_t
harewin_getline(char **buffer, size_t *capacity, FILE *stream)
{
    if (!buffer || !capacity || !stream) { errno = EINVAL; return -1; }
    if (!*buffer || *capacity < 2) {
        char *newbuf = (char *)realloc(*buffer, 128);
        if (!newbuf) { errno = ENOMEM; return -1; }
        *buffer = newbuf;
        *capacity = 128;
    }
    size_t used = 0;
    int ch;
    while ((ch = fgetc(stream)) != EOF) {
        if (used + 1 >= *capacity) {
            if (*capacity > SIZE_MAX / 2) { errno = EOVERFLOW; return -1; }
            size_t newcap = (*capacity) * 2;
            char *newbuf = (char *)realloc(*buffer, newcap);
            if (!newbuf) { errno = ENOMEM; return -1; }
            *buffer = newbuf;
            *capacity = newcap;
        }
        (*buffer)[used++] = (char)ch;
        if (ch == '\n') break;
    }
    if (used == 0 && ch == EOF) return -1;
    (*buffer)[used] = '\0';
    /* 入力サイズは現実的な診断行長と想定。溢れる場合はエラーとする。 */
    if (used > (size_t)PTRDIFF_MAX) { errno = EOVERFLOW; return -1; }
    return (ssize_t)used;
}
#endif
