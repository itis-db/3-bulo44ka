CREATE TABLE users (
                       id SERIAL PRIMARY KEY,
                       username VARCHAR(100) NOT NULL,
                       email VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE articles (
                          id SERIAL PRIMARY KEY,
                          title TEXT NOT NULL,
                          content TEXT NOT NULL,
                          author_id INT NOT NULL,
                          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

                          FOREIGN KEY (author_id) REFERENCES users(id)
);

CREATE TABLE categories (
                            id SERIAL PRIMARY KEY,
                            name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE article_categories (
                                    article_id INT,
                                    category_id INT,

                                    PRIMARY KEY (article_id, category_id),

                                    FOREIGN KEY (article_id) REFERENCES articles(id),
                                    FOREIGN KEY (category_id) REFERENCES categories(id)
);

CREATE TABLE comments (
                          id SERIAL PRIMARY KEY,
                          article_id INT NOT NULL,
                          user_id INT NOT NULL,
                          content TEXT NOT NULL,
                          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

                          FOREIGN KEY (article_id) REFERENCES articles(id),
                          FOREIGN KEY (user_id) REFERENCES users(id)
);


CREATE INDEX idx_articles_author ON articles(author_id);
CREATE INDEX idx_comments_article ON comments(article_id);
CREATE INDEX idx_comments_user ON comments(user_id);


CREATE INDEX idx_articles_created ON articles(created_at);

ALTER TABLE articles ADD COLUMN search_vector tsvector;

UPDATE articles
SET search_vector =
        to_tsvector('russian', coalesce(title, '') || ' ' || coalesce(content, ''));

CREATE INDEX idx_articles_search
    ON articles USING GIN(search_vector);

SELECT id, title,
       ts_rank(search_vector, plainto_tsquery('russian', 'поиск статьи')) AS rank
FROM articles
WHERE search_vector @@ plainto_tsquery('russian', 'поиск статьи')
ORDER BY rank DESC;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX idx_articles_title_trgm
    ON articles USING GIN (title gin_trgm_ops);

CREATE INDEX idx_articles_content_trgm
    ON articles USING GIN (content gin_trgm_ops);

SELECT *
FROM articles
WHERE title ILIKE '%поиск%'
ORDER BY similarity(title, 'поиск') DESC;

INSERT INTO users (username, email) VALUES
                                        ('ivan', 'ivan@mail.com'),
                                        ('anna', 'anna@mail.com');

INSERT INTO articles (title, content, author_id) VALUES
                                                     ('Поиск в PostgreSQL', 'Полнотекстовый поиск позволяет искать слова...', 1),
                                                     ('Индексы в базах данных', 'GIN и B-tree индексы ускоряют поиск...', 2),
                                                     ('Триграммы в PostgreSQL', 'pg_trgm используется для нечеткого поиска...', 1);
EXPLAIN ANALYZE
SELECT *
FROM articles
WHERE search_vector @@ plainto_tsquery('russian', 'поиск');


