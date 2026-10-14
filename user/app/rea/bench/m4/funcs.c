// M4 benchmark functions (AINF-408): small, well-specified, kept out-of-line so every
// optimisation level still has them as separate functions. The reference behaviour for
// the equivalence test is this very file (harness.c links it with ref_ prefixes).
#include <stdint.h>
#include <string.h>

#define F __attribute__((noinline, used))

F uint32_t fnv1a(const char *s) {
  uint32_t h = 0x811c9dc5u;
  while (*s) { h ^= (unsigned char)*s++; h *= 0x01000193u; }
  return h;
}

F void upcase(char *s) {
  for (; *s; s++)
    if (*s >= 'a' && *s <= 'z') *s -= 32;
}

F int count_bits(uint32_t x) {
  int n = 0;
  while (x) { x &= x - 1; n++; }
  return n;
}

F int gcd(int a, int b) {
  if (a < 0) a = -a;
  if (b < 0) b = -b;
  while (b) { int t = a % b; a = b; b = t; }
  return a;
}

F int is_prime(int n) {
  if (n < 2) return 0;
  for (int d = 2; d * d <= n; d++)
    if (n % d == 0) return 0;
  return 1;
}

F void reverse(char *s) {
  size_t n = strlen(s);
  for (size_t i = 0; i < n / 2; i++) { char t = s[i]; s[i] = s[n - 1 - i]; s[n - 1 - i] = t; }
}

F uint16_t checksum16(const uint8_t *p, int n) {
  uint32_t sum = 0;
  for (int i = 0; i + 1 < n; i += 2) sum += (uint32_t)(p[i] << 8 | p[i + 1]);
  if (n & 1) sum += (uint32_t)p[n - 1] << 8;
  while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
  return (uint16_t)~sum;
}

F int bsearch_int(const int *a, int n, int key) {
  int lo = 0, hi = n - 1;
  while (lo <= hi) {
    int mid = lo + (hi - lo) / 2;
    if (a[mid] == key) return mid;
    if (a[mid] < key) lo = mid + 1; else hi = mid - 1;
  }
  return -1;
}

F void sort_ints(int *a, int n) {
  for (int i = 1; i < n; i++) {
    int v = a[i], j = i - 1;
    while (j >= 0 && a[j] > v) { a[j + 1] = a[j]; j--; }
    a[j + 1] = v;
  }
}

F void rot13(char *s) {
  for (; *s; s++) {
    if (*s >= 'a' && *s <= 'z') *s = (char)('a' + (*s - 'a' + 13) % 26);
    else if (*s >= 'A' && *s <= 'Z') *s = (char)('A' + (*s - 'A' + 13) % 26);
  }
}

F int parse_int(const char *s) {
  while (*s == ' ' || *s == '\t') s++;
  int sign = 1, v = 0;
  if (*s == '-' || *s == '+') { if (*s == '-') sign = -1; s++; }
  while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0');
  return sign * v;
}

F int max_subarray(const int *a, int n) {
  int best = a[0], cur = a[0];
  for (int i = 1; i < n; i++) {
    cur = cur + a[i] > a[i] ? cur + a[i] : a[i];
    if (cur > best) best = cur;
  }
  return best;
}

F uint8_t crc8(const uint8_t *p, int n) {
  uint8_t c = 0;
  for (int i = 0; i < n; i++) {
    c ^= p[i];
    for (int b = 0; b < 8; b++) c = (uint8_t)(c & 0x80 ? (c << 1) ^ 0x07 : c << 1);
  }
  return c;
}

F int clamp(int x, int lo, int hi) {
  return x < lo ? lo : x > hi ? hi : x;
}
