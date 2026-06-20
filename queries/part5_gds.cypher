// ============================================================
// Part 5: Graph Algorithms via GDS
// ============================================================


// ===================
// 5.1 PageRank on Movie Graph
// ===================

// Step 1: Materialize CO_RATED edges between movies through shared high-rating users
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(m1) < id(m2)
WITH m1, m2, count(u) AS weight
WHERE size([(m1)<-[:RATED]-() | 1]) > 20
  AND size([(m2)<-[:RATED]-() | 1]) > 20
WITH m1, m2, weight
ORDER BY weight DESC
LIMIT 50000
MERGE (m1)-[co:CO_RATED]-(m2)
SET co.weight = weight;

// Display some of the CO_RATED edges to verify the graph structure
MATCH (m1:Movie)-[co:CO_RATED]->(m2:Movie) RETURN m1, co, m2 LIMIT 30

// Step 2: Create GDS projection based on materialized edges
CALL gds.graph.project(
  'movieGraph',
  'Movie',
  { CO_RATED: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Step 3: Run PageRank — weighted by the number of shared users
// Higher weight = stronger connection between movies.
// Movies with high PageRank are not just popular — they are "bridge" movies
// that connect many clusters of viewers.
CALL gds.pageRank.stream('movieGraph', {
  relationshipWeightProperty: 'weight',
  maxIterations: 20,
  dampingFactor: 0.85
})
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).title AS movie, round(score, 4) AS pageRank
ORDER BY pageRank DESC
LIMIT 20;

// Step 4: Drop projection and temporary edges
CALL gds.graph.drop('movieGraph');
MATCH ()-[co:CO_RATED]-() DELETE co;


// ===================
// 5.2 Louvain Community Detection
// ===================

// Step 1: Materialize SIMILAR edges between users through shared highly-rated movies
// Using rating = 5 and LIMIT 10000 to keep the query manageable on this dataset.
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(u1) < id(u2)
WITH u1, u2, count(m) AS weight
WITH u1, u2, weight
ORDER BY weight DESC
LIMIT 10000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

// Display some of the SIMILAR edges to verify the graph structure
MATCH (u1:User)-[sim:SIMILAR]->(u2:User) RETURN u1, sim, u2 LIMIT 30

// Step 2: Create GDS projection for user similarity graph
CALL gds.graph.project(
  'userSimilarity',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Step 3: Run Louvain to detect communities — write communityId to nodes
CALL gds.louvain.write('userSimilarity', {
  relationshipWeightProperty: 'weight',
  writeProperty: 'communityId'
})
YIELD communityCount, modularity, modularities;

// Step 4: Analyze top 10 largest communities and their preferred genres
// First, get community sizes
MATCH (u:User)
WHERE u.communityId IS NOT NULL
WITH u.communityId AS communityId, count(u) AS size
ORDER BY size DESC
LIMIT 10
// For each community, find the top 3 genres based on high-rated movies
MATCH (u:User {communityId: communityId})-[r:RATED]->(m:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE r.rating >= 4
WITH communityId, size, g.name AS genre, count(*) AS genreCount
ORDER BY communityId, genreCount DESC
WITH communityId, size, collect({genre: genre, count: genreCount})[0..3] AS topGenres
RETURN communityId, size, topGenres;

// Step 5: Drop projection and temporary edges
CALL gds.graph.drop('userSimilarity');
MATCH ()-[sim:SIMILAR]-() DELETE sim;


// ===================
// 5.3 Shortest Path (Dijkstra) between Users
// ===================

// Recreate user similarity graph (same as Louvain)
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(u1) < id(u2)
WITH u1, u2, count(m) AS weight
WITH u1, u2, weight
ORDER BY weight DESC
LIMIT 10000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

CALL gds.graph.project(
  'userGraph',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Run Dijkstra shortest path between two users
// Pair 1: two high-degree users (4277 and 1285)
MATCH (source:User {userId: 4277}), (target:User {userId: 1285})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'weight'
})
YIELD totalCost, nodeIds
RETURN
  [nodeId IN nodeIds | gds.util.asNode(nodeId).userId] AS userPath,
  totalCost,
  size(nodeIds) AS pathLength;

// Pair 2: userId=4277 and userId=549
MATCH (source:User {userId: 4277}), (target:User {userId: 549})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'weight'
})
YIELD totalCost, nodeIds
RETURN
  [nodeId IN nodeIds | gds.util.asNode(nodeId).userId] AS userPath,
  totalCost,
  size(nodeIds) AS pathLength;

// Pair 3: userId=5100 and userId=3539
MATCH (source:User {userId: 5100}), (target:User {userId: 3539})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'weight'
})
YIELD totalCost, nodeIds
RETURN
  [nodeId IN nodeIds | gds.util.asNode(nodeId).userId] AS userPath,
  totalCost,
  size(nodeIds) AS pathLength;

// Cleanup
CALL gds.graph.drop('userGraph');
MATCH ()-[sim:SIMILAR]-() DELETE sim;



// ============================================================================
// 5.3 Shortest Path (Dijkstra) & Global Topology Analysis
// ============================================================================

// 1. Recreate user similarity graph with both Weight (Similarity) and Distance (1/Weight)
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating = 5 AND r2.rating = 5 AND id(u1) < id(u2)
WITH u1, u2, count(m) AS weight
WITH u1, u2, weight
ORDER BY weight DESC
LIMIT 10000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight,
    sim.distance = 1.0 / weight;

// 2. Project the graph using 'distance' as the relationship property for Dijkstra
CALL gds.graph.project(
  'userGraph',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'distance' } }
)
YIELD graphName, nodeCount, relationshipCount;


// ============================================================================
// PART A: TARGETED PAIRS ANALYSIS (WITH VISUALIZATION)
// ============================================================================

// --- PAIR 1: userId=4277 and userId=1285 ---
MATCH (source:User {userId: 4277}), (target:User {userId: 1285})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'distance'
})
YIELD totalCost, nodeIds
WITH totalCost, nodeIds
UNWIND nodeIds AS nodeId
WITH collect(nodeId) AS pathIds
MATCH (u1:User)-[sim:SIMILAR]-(u2:User)
WHERE id(u1) IN pathIds AND id(u2) IN pathIds
RETURN u1, sim, u2;

// --- PAIR 2: userId=10 and userId=3916 ---
MATCH (source:User {userId: 10}), (target:User {userId: 3916})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'distance'
})
YIELD totalCost, nodeIds
WITH totalCost, nodeIds
UNWIND nodeIds AS nodeId
WITH collect(nodeId) AS pathIds
MATCH (u1:User)-[sim:SIMILAR]-(u2:User)
WHERE id(u1) IN pathIds AND id(u2) IN pathIds
RETURN u1, sim, u2;

// --- PAIR 3: userId=97 and userId=36 ---
MATCH (source:User {userId: 97}), (target:User {userId: 36})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'distance'
})
YIELD totalCost, nodeIds
WITH totalCost, nodeIds
UNWIND nodeIds AS nodeId
WITH collect(nodeId) AS pathIds
MATCH (u1:User)-[sim:SIMILAR]-(u2:User)
WHERE id(u1) IN pathIds AND id(u2) IN pathIds
RETURN u1, sim, u2;


// ============================================================================
// PART B: GLOBAL TOPOLOGY & DISTANCE DISTRIBUTION
// ============================================================================

// 1. Calculate weighted shortest path steps (hops) distribution for ALL connected pairs
CALL gds.allShortestPaths.stream('userGraph', {
  relationshipWeightProperty: 'distance'
})
YIELD sourceNodeId, targetNodeId, distance AS totalDijkstraCost
WHERE totalDijkstraCost > 0 AND sourceNodeId < targetNodeId

MATCH (source:User) WHERE id(source) = sourceNodeId
MATCH (target:User) WHERE id(target) = targetNodeId

MATCH path = shortestPath((source)-[:SIMILAR*]-(target))
WITH length(path) AS dijkstraHops

WITH dijkstraHops, count(*) AS pairCount
ORDER BY dijkstraHops ASC

WITH collect({hops: dijkstraHops, count: pairCount}) AS rows, sum(pairCount) AS totalPairs
UNWIND rows AS row
RETURN 
  row.hops AS hops, 
  row.count AS pairCount,
  round(row.count * 100.0 / totalPairs, 2) AS percentageOfPairs;

// 2. Network Connectivity Analysis (Connected vs Disconnected Pairs)
MATCH (u:User)
WITH count(u) AS N
WITH (N * (N - 1) / 2) AS theoreticalTotal, 212226 AS connectedPairs
RETURN 
  theoreticalTotal,
  connectedPairs,
  (theoreticalTotal - connectedPairs) AS disconnectedPairs,
  round((theoreticalTotal - connectedPairs) * 100.0 / theoreticalTotal, 2) AS percentageOfDisconnected;


// ============================================================================
// CLEANUP
// ============================================================================
CALL gds.graph.drop('userGraph');
MATCH ()-[sim:SIMILAR]-() DELETE sim;