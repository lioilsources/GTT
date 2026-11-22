package steps

import (
	"container/heap"
	"log/slog"
	"math"

	"citypack/internal/geo"
)

// connectKeptDirected makes the kept network strongly connected where the full graph allows it:
// for every stray strongly connected component of kept roads it promotes the shortest alley paths
// main → stray and stray → main, both respecting one-ways. connectKept only joins the network
// undirected; an organic one-way grid (Prague) still leaves islands that a car cannot drive
// into or out of. A component without both paths (a one-way leaving the area) stays as it is.
func connectKeptDirected(g *workGraph) {
	adj := make([][]int, len(g.nodes))
	for i, ed := range g.edges {
		adj[ed.from] = append(adj[ed.from], i)
		if ed.to != ed.from {
			adj[ed.to] = append(adj[ed.to], i)
		}
	}
	skip := make([]bool, len(g.nodes))
	promoted, gaveUp := 0, 0
	for iter := 0; iter < 10000; iter++ {
		comp, main := keptSCC(g, adj)
		if main < 0 {
			break
		}
		// Smallest stray component not given up yet; ties go to the lowest node index.
		members := map[int][]int{}
		for n, c := range comp {
			if c >= 0 && c != main {
				members[c] = append(members[c], n)
			}
		}
		stray, strayN, strayMin := -1, math.MaxInt, math.MaxInt
		for c, ns := range members {
			if skip[ns[0]] {
				continue
			}
			if len(ns) < strayN || (len(ns) == strayN && ns[0] < strayMin) {
				stray, strayN, strayMin = c, len(ns), ns[0]
			}
		}
		if stray < 0 {
			break
		}
		var mainNodes []int
		for n, c := range comp {
			if c == main {
				mainNodes = append(mainNodes, n)
			}
		}
		in := func(c int) func(int) bool { return func(n int) bool { return comp[n] == c } }
		there := dijkstraDirected(g, adj, mainNodes, in(stray))
		back := dijkstraDirected(g, adj, members[stray], in(main))
		if there == nil || back == nil {
			for _, n := range members[stray] {
				skip[n] = true
			}
			gaveUp++
			continue
		}
		for _, ei := range append(there, back...) {
			if !g.edges[ei].kept {
				g.edges[ei].kept = true
				promoted++
			}
		}
	}
	slog.Info("roads: one-way connectors promoted to kept", "edges", promoted, "stray_components_left", gaveUp)
}

// step returns the node reached from n over edge ei, or -1 when the edge's one-way forbids it.
func step(ed workEdge, n int) int {
	switch {
	case ed.from == n && ed.oneway >= 0:
		return ed.to
	case ed.to == n && ed.oneway <= 0:
		return ed.from
	}
	return -1
}

// keptSCC labels nodes by strongly connected component of the directed kept network
// (-1 = no kept edge at the node) and returns the component with the most nodes.
func keptSCC(g *workGraph, adj [][]int) ([]int, int) {
	n := len(g.nodes)
	touched := make([]bool, n)
	for _, ed := range g.edges {
		if ed.kept {
			touched[ed.from], touched[ed.to] = true, true
		}
	}
	// Iterative Tarjan.
	index := make([]int, n)
	low := make([]int, n)
	onStack := make([]bool, n)
	comp := make([]int, n)
	for i := range index {
		index[i], comp[i] = -1, -1
	}
	var stack []int
	next, ncomp := 0, 0
	size := map[int]int{}
	type frame struct{ node, edge int }
	for root := 0; root < n; root++ {
		if !touched[root] || index[root] >= 0 {
			continue
		}
		call := []frame{{root, 0}}
		index[root], low[root] = next, next
		next++
		stack = append(stack, root)
		onStack[root] = true
		for len(call) > 0 {
			f := &call[len(call)-1]
			v := f.node
			if f.edge < len(adj[v]) {
				ed := g.edges[adj[v][f.edge]]
				f.edge++
				if !ed.kept {
					continue
				}
				w := step(ed, v)
				if w < 0 || w == v {
					continue
				}
				if index[w] < 0 {
					index[w], low[w] = next, next
					next++
					stack = append(stack, w)
					onStack[w] = true
					call = append(call, frame{w, 0})
				} else if onStack[w] && index[w] < low[v] {
					low[v] = index[w]
				}
				continue
			}
			if low[v] == index[v] {
				for {
					w := stack[len(stack)-1]
					stack = stack[:len(stack)-1]
					onStack[w] = false
					comp[w] = ncomp
					size[ncomp]++
					if w == v {
						break
					}
				}
				ncomp++
			}
			call = call[:len(call)-1]
			if len(call) > 0 {
				u := call[len(call)-1].node
				if low[v] < low[u] {
					low[u] = low[v]
				}
			}
		}
	}
	main, mainN := -1, 0
	for c := 0; c < ncomp; c++ {
		if size[c] > mainN {
			main, mainN = c, size[c]
		}
	}
	return comp, main
}

// dijkstraDirected is dijkstra over all edges respecting one-ways; returns the edge indices of
// the shortest path from any source to the first target, nil when there is none.
func dijkstraDirected(g *workGraph, adj [][]int, sources []int, target func(int) bool) []int {
	dist := make([]float64, len(g.nodes))
	via := make([]int, len(g.nodes))
	prev := make([]int, len(g.nodes))
	for i := range dist {
		dist[i] = math.Inf(1)
		via[i] = -1
	}
	q := &pq{}
	for _, s := range sources {
		dist[s] = 0
		heap.Push(q, pqItem{s, 0})
	}
	for q.Len() > 0 {
		it := heap.Pop(q).(pqItem)
		if it.d > dist[it.node] {
			continue
		}
		if target(it.node) && it.d > 0 {
			var path []int
			for n := it.node; via[n] >= 0; n = prev[n] {
				path = append(path, via[n])
			}
			return path
		}
		for _, ei := range adj[it.node] {
			ed := g.edges[ei]
			o := step(ed, it.node)
			if o < 0 || o == it.node {
				continue
			}
			d := it.d + geo.PolylineLength(ed.pts)
			if d < dist[o] {
				dist[o], via[o], prev[o] = d, ei, it.node
				heap.Push(q, pqItem{o, d})
			}
		}
	}
	return nil
}
