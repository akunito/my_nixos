// Driver so the corpus binaries reference every function (and the optimiser keeps them).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

uint32_t fnv1a(const char *); void upcase(char *); int count_bits(uint32_t); int gcd(int, int);
int is_prime(int); void reverse(char *); uint16_t checksum16(const uint8_t *, int);
int bsearch_int(const int *, int, int); void sort_ints(int *, int); void rot13(char *);
int parse_int(const char *); int max_subarray(const int *, int); uint8_t crc8(const uint8_t *, int);
int clamp(int, int, int);

int main(int argc, char **argv) {
  char buf[128];
  snprintf(buf, sizeof buf, "%s", argc > 1 ? argv[1] : "hello world");
  int a[8] = {5, -3, 7, 1, -2, 9, 0, 4};
  sort_ints(a, 8);
  upcase(buf); reverse(buf); rot13(buf);
  printf("%s %08x %d %d %d %04x %d %d %d %02x %d\n", buf, fnv1a(buf), count_bits((uint32_t)argc),
         gcd(argc * 12, 18), is_prime(argc + 6), checksum16((const uint8_t *)buf, (int)strlen(buf)),
         bsearch_int(a, 8, 7), parse_int(argc > 2 ? argv[2] : " -42"), max_subarray(a, 8),
         crc8((const uint8_t *)buf, (int)strlen(buf)), clamp(argc * 100, 0, 255));
  return 0;
}
