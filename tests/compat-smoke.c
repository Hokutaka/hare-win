/* Windows互換層の単体テスト。Hareのコード生成とは切り離す。 */
#include "harewin-compat.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
    char *args[] = {"harec", "-v", "-o", "test.ssa", "athena3.ha"};
    assert(harewin_getopt(5, args, "o:v") == 'v');
    assert(harewin_getopt(5, args, "o:v") == 'o');
    assert(strcmp(harewin_optarg, "test.ssa") == 0);
    assert(harewin_getopt(5, args, "o:v") == -1);
    assert(harewin_optind == 4);

    FILE *input = harewin_fmemopen("hello\n", 6, "r");
    assert(input);
    char *line = NULL;
    size_t cap = 0;
    assert(harewin_getline(&line, &cap, input) == 6);
    assert(strcmp(line, "hello\n") == 0);
    assert(harewin_getline(&line, &cap, input) == -1);
    free(line);
    fclose(input);
    puts("PASS: harec Windows host compatibility smoke");
    return 0;
}
