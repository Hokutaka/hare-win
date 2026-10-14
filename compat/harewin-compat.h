/*
 * Hare-Windows Phase 1: harec ホスト側のPOSIX互換層。
 * Hare言語・ABI・Windows向けHareランタイムは変更しない。
 * このファイルは Windows UCRT64 のCコンパイラ向け。
 */
#ifndef HAREWIN_COMPAT_H
#define HAREWIN_COMPAT_H

#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <io.h>
#ifndef S_ISDIR
# if defined(S_IFMT) && defined(S_IFDIR)
#  define S_ISDIR(mode) (((mode) & S_IFMT) == S_IFDIR)
# else
#  define S_ISDIR(mode) (((mode) & _S_IFMT) == _S_IFDIR)
# endif
#endif
#ifndef S_ISREG
# if defined(S_IFMT) && defined(S_IFREG)
#  define S_ISREG(mode) (((mode) & S_IFMT) == S_IFREG)
# else
#  define S_ISREG(mode) (((mode) & _S_IFMT) == _S_IFREG)
# endif
#endif

/* 意図的に prefix を付け、既存CRTとの重複シンボルを避ける。 */
extern char *harewin_optarg;
extern int harewin_optind;
extern int harewin_optopt;
int harewin_getopt(int argc, char *const argv[], const char *optstring);
FILE *harewin_fmemopen(const void *buffer, size_t length, const char *mode);
ssize_t harewin_getline(char **buffer, size_t *capacity, FILE *stream);

#define getopt harewin_getopt
#define optarg harewin_optarg
#define optind harewin_optind
#define optopt harewin_optopt
#define fmemopen harewin_fmemopen
#define getline harewin_getline

/* MinGW-w64は互換関数を提供するが、名前は明示しておく。 */
#define fileno _fileno
#define isatty _isatty
#endif /* _WIN32 */
#endif /* HAREWIN_COMPAT_H */
