// M1 corpus program (C): typical libc use + own logic, so stripped static builds carry
// many libc functions for signature/FID recovery and a few of our own to name.
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct rec { char key[32]; long value; };

static uint32_t fnv1a(const char *s) {
  uint32_t h = 0x811c9dc5u;
  while (*s) { h ^= (unsigned char)*s++; h *= 0x01000193u; }
  return h;
}

static int cmp_rec(const void *a, const void *b) {
  const struct rec *x = a, *y = b;
  return strcmp(x->key, y->key);
}

static long parse_line(const char *line, struct rec *out) {
  const char *eq = strchr(line, '=');
  if (!eq || (size_t)(eq - line) >= sizeof out->key) return -1;
  memcpy(out->key, line, (size_t)(eq - line));
  out->key[eq - line] = 0;
  char *end;
  out->value = strtol(eq + 1, &end, 0);
  return *end == 0 || *end == '\n' ? 0 : -1;
}

static void upcase(char *s) { for (; *s; s++) *s = (char)toupper((unsigned char)*s); }

int main(int argc, char **argv) {
  struct rec *recs = calloc(64, sizeof *recs);
  size_t n = 0;
  char buf[256];
  FILE *f = argc > 1 ? fopen(argv[1], "r") : stdin;
  if (!f) { perror("fopen"); return 1; }
  while (n < 64 && fgets(buf, sizeof buf, f))
    if (parse_line(buf, &recs[n]) == 0) n++;
  qsort(recs, n, sizeof *recs, cmp_rec);
  time_t now = time(NULL);
  for (size_t i = 0; i < n; i++) {
    upcase(recs[i].key);
    printf("%s=%ld %08x %s", recs[i].key, recs[i].value, fnv1a(recs[i].key), ctime(&now));
  }
  free(recs);
  return 0;
}
