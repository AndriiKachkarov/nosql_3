// ============================================================
// Part 2: Data Loading — indexes, constraints, nodes and edges
// ============================================================

// --- Step 1: Create uniqueness constraints (also serve as indexes) ---

CREATE CONSTRAINT user_id_unique IF NOT EXISTS
FOR (u:User) REQUIRE u.userId IS UNIQUE;

CREATE CONSTRAINT movie_id_unique IF NOT EXISTS
FOR (m:Movie) REQUIRE m.movieId IS UNIQUE;

CREATE CONSTRAINT genre_name_unique IF NOT EXISTS
FOR (g:Genre) REQUIRE g.name IS UNIQUE;


// --- Step 2: Load User nodes ---
// Each row maps to a User node with demographic properties.
// MERGE prevents duplicates if the script is run multiple times.

LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
MERGE (u:User {userId: toInteger(row.userId)})
SET u.gender = row.gender,
    u.age = toInteger(row.age),
    u.occupation = toInteger(row.occupation);


// --- Step 3: Load Movie nodes ---
// Title contains the year in parentheses, e.g. "Toy Story (1995)".
// We extract the year as a separate integer property for filtering.

LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
MERGE (m:Movie {movieId: toInteger(row.movieId)})
SET m.title = trim(row.title),
    m.year = CASE 
      WHEN row.title =~ '.*\\(\\d{4}\\).*' 
      THEN toInteger(apoc.text.regexGroups(row.title, '.*\\((\\d{4})\\).*')[0][1])
      ELSE null
    END;


// --- Step 4.1: Load ONLY Genre nodes first (Prevents Eager operations & Locks) ---
// This ensures all Genre nodes are created before creating relationships.

LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
WITH split(row.genres, '|') AS genreList
UNWIND genreList AS genreName
MERGE (g:Genre {name: genreName});


// --- Step 4.2: Create HAS_GENRE relationships ---

LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
MATCH (m:Movie {movieId: toInteger(row.movieId)})
WITH m, split(row.genres, '|') AS genreList
UNWIND genreList AS genreName
MATCH (g:Genre {name: genreName})
CREATE (m)-[:HAS_GENRE]->(g);


// --- Step 5: Load RATED relationships in batches ---
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM 'file:///ratings.csv' AS row RETURN row",
  "MATCH (u:User {userId: toInteger(row.userId)})
   MATCH (m:Movie {movieId: toInteger(row.movieId)})
   CREATE (u)-[r:RATED {rating: toFloat(row.rating), timestamp: toInteger(row.timestamp)}]->(m)",
  {batchSize: 5000, parallel: false}
);


// --- Step 6: Verify loaded data ---

MATCH (u:User) RETURN count(u) AS users;
// Expected: 6040

MATCH (m:Movie) RETURN count(m) AS movies;
// Expected: 3883

MATCH (g:Genre) RETURN count(g) AS genres;
// Expected: 18

MATCH ()-[r:RATED]->() RETURN count(r) AS ratings;
// Expected: 1000209
