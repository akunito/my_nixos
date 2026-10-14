// M1 corpus program (Go): maps, sorting, fmt, goroutines, json.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
)

type entry struct {
	Word  string `json:"word"`
	Count int    `json:"count"`
}

func count(lines []string) map[string]int {
	var mu sync.Mutex
	var wg sync.WaitGroup
	out := map[string]int{}
	for _, l := range lines {
		wg.Add(1)
		go func(l string) {
			defer wg.Done()
			for _, w := range strings.Fields(strings.ToLower(l)) {
				mu.Lock()
				out[w]++
				mu.Unlock()
			}
		}(l)
	}
	wg.Wait()
	return out
}

func main() {
	var lines []string
	sc := bufio.NewScanner(os.Stdin)
	for sc.Scan() {
		lines = append(lines, sc.Text())
	}
	var es []entry
	for w, c := range count(lines) {
		es = append(es, entry{w, c})
	}
	sort.Slice(es, func(i, j int) bool { return es[i].Count > es[j].Count })
	b, err := json.Marshal(es)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(string(b))
}
