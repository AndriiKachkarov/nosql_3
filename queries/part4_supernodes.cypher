// ============================================================
// Part 4: Supernode Detection
// ============================================================

// --- Step 1: Find Movie nodes with the highest number of RATED edges ---
// Movies that many users rated become supernodes — every traversal
// through them expands to thousands of paths.

MATCH (m:Movie)
RETURN m.title AS title,
       m.movieId AS movieId,
       size([(m)<-[:RATED]-() | 1]) AS ratingCount
ORDER BY ratingCount DESC
LIMIT 20;


// --- Step 2: Find User nodes with the highest number of RATED edges ---
// Some "power users" rated hundreds or even thousands of movies.

MATCH (u:User)
RETURN u.userId AS userId,
       size([(u)-[:RATED]->() | 1]) AS ratingCount
ORDER BY ratingCount DESC
LIMIT 20;


// --- Step 3: Check Genre nodes — potential supernodes ---
// Each Genre node is connected to many movies via HAS_GENRE.
// Genre nodes also act as supernodes when traversing genre-based queries.

MATCH (g:Genre)
RETURN g.name AS genre,
       size([(g)<-[:HAS_GENRE]-() | 1]) AS movieCount
ORDER BY movieCount DESC;


// --- Step 4: Combined view — all node types sorted by total degree ---

    MATCH (n)
    WHERE n:Movie OR n:User OR n:Genre
    WITH n,
        labels(n)[0] AS label,
        size([(n)--() | 1]) AS degree
    RETURN label,
        CASE
            WHEN n:User THEN 'User ' + toString(n.userId)
            WHEN n:Movie THEN n.title
            WHEN n:Genre THEN n.name
        END AS node,
        degree
    ORDER BY degree DESC
    LIMIT 30;
