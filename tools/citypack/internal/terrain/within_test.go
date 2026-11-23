package terrain

import (
	"reflect"
	"testing"
)

// A chain 0-1-2-3-4 with 50 m links and a 10 m spur 2-5: within 60 m of vertex 1 lie 0, 1, 2, 5.
func TestWithin(t *testing.T) {
	links := []link{{a: 0, b: 1, l: 50}, {a: 1, b: 2, l: 50}, {a: 2, b: 3, l: 50}, {a: 3, b: 4, l: 50}, {a: 2, b: 5, l: 10}}
	adj := make([][]int, 6)
	for k, l := range links {
		adj[l.a] = append(adj[l.a], k)
		adj[l.b] = append(adj[l.b], k)
	}
	if got, want := within(links, adj, []int{1}, 60), []int{0, 1, 2, 5}; !reflect.DeepEqual(got, want) {
		t.Fatalf("within 60 m of 1 = %v, want %v", got, want)
	}
	if got, want := within(links, adj, []int{0, 4}, 49), []int{0, 4}; !reflect.DeepEqual(got, want) {
		t.Fatalf("within 49 m of 0 and 4 = %v, want %v", got, want)
	}
}
