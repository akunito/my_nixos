// M4 equivalence harness: compile with -DFN_<name>; links the candidate as `cand` and the
// original (funcs.c) with ref_ prefixed symbols. Prints PASS or FAIL <case>; exit 0/1.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t rs = 12345;
static uint32_t rnd(void) { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; }
static void rstr(char *b, int max, int lo, int hi) {
  int n = (int)(rnd() % (uint32_t)max);
  for (int i = 0; i < n; i++) b[i] = (char)(lo + (int)(rnd() % (uint32_t)(hi - lo + 1)));
  b[n] = 0;
}
#define FAIL(...) do { printf("FAIL "); printf(__VA_ARGS__); printf("\n"); return 1; } while (0)

#if defined(FN_fnv1a)
uint32_t cand(const char *); uint32_t ref_fnv1a(const char *);
int main(void) { char b[64];
  for (int i = 0; i < 2000; i++) { rstr(b, 60, 1, 255); if (cand(b) != ref_fnv1a(b)) FAIL("%d", i); }
  puts("PASS"); return 0; }
#elif defined(FN_upcase) || defined(FN_reverse) || defined(FN_rot13)
void cand(char *);
#if defined(FN_upcase)
void ref_upcase(char *);
#define REF ref_upcase
#elif defined(FN_reverse)
void ref_reverse(char *);
#define REF ref_reverse
#else
void ref_rot13(char *);
#define REF ref_rot13
#endif
int main(void) { char a[80], b[80];
  for (int i = 0; i < 2000; i++) { rstr(a, 70, 32, 126); memcpy(b, a, sizeof a); cand(a); REF(b); if (strcmp(a, b)) FAIL("%d", i); }
  puts("PASS"); return 0; }
#elif defined(FN_count_bits)
int cand(uint32_t); int ref_count_bits(uint32_t);
int main(void) { for (int i = 0; i < 5000; i++) { uint32_t x = i < 40 ? (i < 32 ? 1u << i : (uint32_t)i * 0x01010101u) : rnd(); if (cand(x) != ref_count_bits(x)) FAIL("%u", x); } puts("PASS"); return 0; }
#elif defined(FN_gcd)
int cand(int, int); int ref_gcd(int, int);
int main(void) { for (int i = 0; i < 5000; i++) { int a = (int)(rnd() % 2001) - 1000, b = (int)(rnd() % 2001) - 1000; if (cand(a, b) != ref_gcd(a, b)) FAIL("%d %d", a, b); } puts("PASS"); return 0; }
#elif defined(FN_is_prime)
int cand(int); int ref_is_prime(int);
int main(void) { for (int n = -5; n < 5000; n++) if (!!cand(n) != !!ref_is_prime(n)) FAIL("%d", n); puts("PASS"); return 0; }
#elif defined(FN_checksum16) || defined(FN_crc8)
#if defined(FN_checksum16)
uint16_t cand(const uint8_t *, int); uint16_t ref_checksum16(const uint8_t *, int);
#define REF ref_checksum16
#else
uint8_t cand(const uint8_t *, int); uint8_t ref_crc8(const uint8_t *, int);
#define REF ref_crc8
#endif
int main(void) { uint8_t p[64];
  for (int i = 0; i < 2000; i++) { int n = (int)(rnd() % 64); for (int j = 0; j < n; j++) p[j] = (uint8_t)rnd(); if (cand(p, n) != REF(p, n)) FAIL("%d n=%d", i, n); }
  puts("PASS"); return 0; }
#elif defined(FN_bsearch_int)
int cand(const int *, int, int); int ref_bsearch_int(const int *, int, int);
int main(void) { int a[40];
  for (int i = 0; i < 2000; i++) { int n = (int)(rnd() % 40); int v = -50; for (int j = 0; j < n; j++) { v += 1 + (int)(rnd() % 5); a[j] = v; }
    int key = (int)(rnd() % 200) - 60; int r = cand(a, n, key), e = ref_bsearch_int(a, n, key);
    if ((r < 0) != (e < 0) || (r >= 0 && a[r] != key)) FAIL("%d", i); }
  puts("PASS"); return 0; }
#elif defined(FN_sort_ints)
void cand(int *, int); void ref_sort_ints(int *, int);
int main(void) { int a[50], b[50];
  for (int i = 0; i < 2000; i++) { int n = (int)(rnd() % 50); for (int j = 0; j < n; j++) a[j] = b[j] = (int)(rnd() % 200) - 100; cand(a, n); ref_sort_ints(b, n);
    if (memcmp(a, b, sizeof(int) * (size_t)n)) FAIL("%d", i); }
  puts("PASS"); return 0; }
#elif defined(FN_parse_int)
int cand(const char *); int ref_parse_int(const char *);
int main(void) { char b[40]; const char *fixed[] = {"", "0", "-0", "+7", "  42", "\t-13x", "12 34", "-", "abc", "999999"};
  for (int i = 0; i < 10; i++) if (cand(fixed[i]) != ref_parse_int(fixed[i])) FAIL("'%s'", fixed[i]);
  for (int i = 0; i < 3000; i++) { rstr(b, 12, '0', '9'); if (i % 3 == 0) b[0] = '-'; if (cand(b) != ref_parse_int(b)) FAIL("'%s'", b); }
  puts("PASS"); return 0; }
#elif defined(FN_max_subarray)
int cand(const int *, int); int ref_max_subarray(const int *, int);
int main(void) { int a[40];
  for (int i = 0; i < 3000; i++) { int n = 1 + (int)(rnd() % 39); for (int j = 0; j < n; j++) a[j] = (int)(rnd() % 41) - 20; if (cand(a, n) != ref_max_subarray(a, n)) FAIL("%d", i); }
  puts("PASS"); return 0; }
#elif defined(FN_clamp)
int cand(int, int, int); int ref_clamp(int, int, int);
int main(void) { for (int i = 0; i < 5000; i++) { int lo = (int)(rnd() % 100) - 50, hi = lo + (int)(rnd() % 100), x = (int)(rnd() % 300) - 150; if (cand(x, lo, hi) != ref_clamp(x, lo, hi)) FAIL("%d %d %d", x, lo, hi); } puts("PASS"); return 0; }
#else
#error "define FN_<name>"
#endif
