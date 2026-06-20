// ============================================================
// Part 3: Cypher Queries of Increasing Complexity
// ============================================================


// --- Query 1 (Basic): Thriller movies with average rating above 4.0 ---
// Traverse Movie->Genre to filter by "Thriller", then aggregate
// all RATED edges pointing to each movie to compute the average.

MATCH (m:Movie)-[:HAS_GENRE]->(g:Genre {name: 'Thriller'})
MATCH (m)<-[r:RATED]-()
WITH m.title AS title, avg(r.rating) AS avgRating, count(r) AS ratingCount
WHERE avgRating > 4.0
RETURN title, round(avgRating, 2) AS avgRating, ratingCount
ORDER BY avgRating DESC, ratingCount DESC;


// --- Query 2 (Basic): Users who gave a rating of 5 to more than 50 movies ---
// Filter RATED edges by rating = 5, group by user, keep those with count > 50.

MATCH (u:User)-[r:RATED]->(m:Movie)
WHERE r.rating = 5
WITH u.userId AS userId, count(m) AS fiveStarCount
WHERE fiveStarCount > 50
RETURN userId, fiveStarCount
ORDER BY fiveStarCount DESC;


// --- Query 3 (Medium): Movies both userId=1 and userId=2 rated >= 4 ---
// Match two separate rating paths to the same movie, both with rating >= 4.

MATCH (u1:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User {userId: 2})
WHERE r1.rating >= 4 AND r2.rating >= 4
RETURN m.title AS title,
       r1.rating AS user1Rating,
       r2.rating AS user2Rating
ORDER BY (r1.rating + r2.rating) DESC, title;


// --- Query 4 (Medium): Genres with consistently high ratings — avg and count ---
// Traverse Genre<-Movie<-RATED, aggregate per genre.
// Useful to see which genres are both popular and highly rated.

MATCH (g:Genre)<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-()
WITH g.name AS genre,
     avg(r.rating) AS avgRating,
     count(r) AS totalRatings
RETURN genre,
       round(avgRating, 2) AS avgRating,
       totalRatings
ORDER BY avgRating DESC;


// --- Query 5 (Complex): "Users with similar taste also watched" recommendation ---
// For userId=1:
// 1. Find movies the target user rated highly (>= 4).
// 2. Find other users who also rated those movies highly — "similar users".
// 3. Find movies those similar users rated highly that the target user hasn't seen.
// 4. Rank by how many similar users liked each recommended movie.

MATCH (target:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(similar:User)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND target <> similar
WITH target, similar, count(m) AS sharedMovies
WHERE sharedMovies >= 3
WITH target, similar
ORDER BY sharedMovies DESC
LIMIT 100
MATCH (similar)-[r:RATED]->(rec:Movie)
WHERE r.rating >= 4
  AND NOT EXISTS { MATCH (target)-[:RATED]->(rec) }
RETURN rec.title AS recommendedMovie,
       count(DISTINCT similar) AS recommendedBy,
       round(avg(r.rating), 2) AS avgRating
ORDER BY recommendedBy DESC, avgRating DESC
LIMIT 20;


// --- Query 6 (Complex): Shortest path between two users through shared movies ---
// Uses the built-in shortestPath function. The path goes through RATED edges:
// User1 -[:RATED]-> Movie <-[:RATED]- User2
// Path length 2 = users share a movie directly.
// Path length 4 = one intermediary user (User1->Movie1<-UserX->Movie2<-User2).
// Path length 6 = two intermediary users.

MATCH (u1:User {userId: 1}), (u2:User {userId: 100}),
      path = shortestPath((u1)-[:RATED*]-(u2))
RETURN [n IN nodes(path) |
         CASE
           WHEN n:User THEN 'User ' + toString(n.userId)
           WHEN n:Movie THEN n.title
           ELSE 'Unknown'
         END
       ] AS pathNodes,
       length(path) AS pathLength;
