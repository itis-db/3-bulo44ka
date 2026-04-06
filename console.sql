CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

-- 1. Таблица авторов
CREATE TABLE authors (
                         author_id SERIAL PRIMARY KEY,
                         full_name VARCHAR(100) NOT NULL,
                         email VARCHAR(100) UNIQUE NOT NULL,
                         created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Таблица категорий
CREATE TABLE categories (
                            category_id SERIAL PRIMARY KEY,
                            category_name VARCHAR(50) NOT NULL UNIQUE,
                            description TEXT
);

-- 3. Главная таблица статей (3НФ: все атрибуты зависят от article_id)
CREATE TABLE articles (
                          article_id SERIAL PRIMARY KEY,
                          title VARCHAR(200) NOT NULL,
                          content TEXT NOT NULL,
                          summary TEXT,
                          author_id INTEGER NOT NULL REFERENCES authors(author_id),
                          category_id INTEGER NOT NULL REFERENCES categories(category_id),
                          views_count INTEGER DEFAULT 0,
                          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Таблица для тегов (связь многие-ко-многим)
CREATE TABLE tags (
                      tag_id SERIAL PRIMARY KEY,
                      tag_name VARCHAR(50) NOT NULL UNIQUE
);

-- 5. Связующая таблица (для соблюдения 3НФ)
CREATE TABLE article_tags (
                              article_id INTEGER REFERENCES articles(article_id) ON DELETE CASCADE,
                              tag_id INTEGER REFERENCES tags(tag_id) ON DELETE CASCADE,
                              PRIMARY KEY (article_id, tag_id)
);

-- Индексы для внешних ключей и часто используемых полей
CREATE INDEX idx_articles_author_id ON articles(author_id);
CREATE INDEX idx_articles_category_id ON articles(category_id);
CREATE INDEX idx_articles_created_at ON articles(created_at DESC);
CREATE INDEX idx_articles_views_count ON articles(views_count DESC);

-- GIN индекс для полнотекстового поиска с русским словарём
CREATE INDEX idx_articles_fts ON articles
    USING GIN (to_tsvector('russian', title || ' ' || COALESCE(content, '')));

-- GIN индекс для триграмм (поиск по частичному совпадению)
CREATE INDEX idx_articles_title_trgm ON articles USING GIN (title gin_trgm_ops);
CREATE INDEX idx_articles_content_trgm ON articles USING GIN (content gin_trgm_ops);

-- Комбинированный индекс для релевантности и сортировки
CREATE INDEX idx_articles_relevance ON articles(views_count DESC, created_at DESC);

-- Добавление авторов
INSERT INTO authors (full_name, email) VALUES
                                           ('Иван Петров', 'ivan.petrov@example.com'),
                                           ('Мария Сидорова', 'maria.s@example.com'),
                                           ('Алексей Смирнов', 'alex.smirnov@example.com'),
                                           ('Елена Козлова', 'elena.koz@example.com');

-- Добавление категорий
INSERT INTO categories (category_name, description) VALUES
                                                        ('Программирование', 'Статьи о разработке ПО'),
                                                        ('Базы данных', 'PostgreSQL, MySQL, оптимизация'),
                                                        ('Искусственный интеллект', 'ML, нейросети, ChatGPT'),
                                                        ('Веб-разработка', 'Frontend, backend, API');

-- Добавление статей с реалистичным содержанием
INSERT INTO articles (title, content, summary, author_id, category_id, views_count) VALUES
                                                                                        ('Оптимизация запросов в PostgreSQL',
                                                                                         'Полнотекстовый поиск в PostgreSQL позволяет эффективно работать с текстовыми данными. Использование GIN индексов значительно ускоряет поиск. Для русского языка необходимо настроить конфигурацию russian.',
                                                                                         'Как ускорить полнотекстовый поиск', 1, 2, 150),

                                                                                        ('Введение в машинное обучение',
                                                                                         'Машинное обучение это подраздел искусственного интеллекта. Нейронные сети обучаются на больших объемах данных. PyTorch и TensorFlow основные инструменты.',
                                                                                         'Основы ML для начинающих', 2, 3, 230),

                                                                                        ('Создание REST API на Python',
                                                                                         'FastAPI и Django REST framework позволяют быстро создавать высокопроизводительные API. Важно правильно обрабатывать ошибки и валидировать данные.',
                                                                                         'Практическое руководство по API', 3, 4, 89),

                                                                                        ('Индексы в базах данных',
                                                                                         'B-tree индексы подходят для точного поиска, а GIN для полнотекстового. Триграммы помогают искать по частичному совпадению слов.',
                                                                                         'Типы индексов и их применение', 1, 2, 312),

                                                                                        ('Нейросети для обработки текста',
                                                                                         'Трансформеры и BERT изменили подход к обработке естественного языка. Полнотекстовый поиск с морфологией русского языка требует настройки словарей.',
                                                                                         'Современные NLP подходы', 4, 3, 176);

-- Добавление тегов
INSERT INTO tags (tag_name) VALUES
                                ('postgresql'), ('индексы'), ('python'), ('ml'), ('api'), ('nlp');

-- Связь статей с тегами
INSERT INTO article_tags VALUES
                             (1, 1), (1, 2),
                             (2, 4), (2, 6),
                             (3, 3), (3, 5),
                             (4, 1), (4, 2),
                             (5, 4), (5, 6);

-- Полнотекстовый поиск по русскому языку
EXPLAIN ANALYZE
SELECT
    article_id,
    title,
    content,
    ts_rank(to_tsvector('russian', title || ' ' || content),
            plainto_tsquery('russian', 'поиск индексов')) AS relevance
FROM articles
WHERE to_tsvector('russian', title || ' ' || content) @@
      plainto_tsquery('russian', 'поиск индексов')
ORDER BY relevance DESC;

-- https://explain.tensor.ru/archive/explain/d371d8a456bb1546957f6072583beaad:0:2026-04-06

-- Поиск по началу слова с помощью триграмм
EXPLAIN ANALYZE
SELECT
    article_id,
    title,
    content,
    similarity(title, 'полнотекст') AS similarity_score
FROM articles
WHERE title % 'полнотекст'  -- Оператор схожести
   OR title LIKE 'полнотекст%'
ORDER BY similarity_score DESC
LIMIT 10;

-- https://explain.tensor.ru/archive/explain/4b8a08933de4d0d264d61733090619c2:0:2026-04-06

-- Максимально релевантные результаты
EXPLAIN ANALYZE
WITH fts_search AS (
    SELECT
        article_id,
        title,
        ts_rank(to_tsvector('russian', title || ' ' || content),
                to_tsquery('russian', 'postgresql & оптимизация')) AS fts_score
    FROM articles
    WHERE to_tsvector('russian', title || ' ' || content) @@
          to_tsquery('russian', 'postgresql & оптимизация')
)
SELECT
    a.article_id,
    a.title,
    a.views_count,
    COALESCE(fts_score, 0) as relevance
FROM articles a
         LEFT JOIN fts_search f USING (article_id)
WHERE similarity(a.title, 'postgre') > 0.2 OR fts_score > 0
ORDER BY relevance DESC, a.views_count DESC
LIMIT 20;

-- https://explain.tensor.ru/archive/explain/0732f2bd61e9fc7492a10740a493354a:0:2026-04-06

-- Сложный поиск с фильтрацией
EXPLAIN ANALYZE
SELECT
    a.article_id,
    a.title,
    a.content,
    c.category_name,
    au.full_name as author,
    ts_rank(to_tsvector('russian', a.title || ' ' || a.content),
            to_tsquery('russian', 'нейросеть | обучение')) as relevance
FROM articles a
         JOIN categories c ON a.category_id = c.category_id
         JOIN authors au ON a.author_id = au.author_id
WHERE to_tsvector('russian', a.title || ' ' || a.content) @@
      to_tsquery('russian', 'нейросеть | обучение')
ORDER BY relevance DESC;

--https://explain.tensor.ru/archive/explain/0cadd122e7bcb971ab083cd5189fa71c:0:2026-04-06

-- Тест 1: Поиск по слову с морфологией
SELECT
    title,
    ts_rank_cd(to_tsvector('russian', content),
               to_tsquery('russian', 'индексах')) as relevance
FROM articles
WHERE to_tsvector('russian', content) @@ to_tsquery('russian', 'индексах');

-- Тест 2: Поиск по частичному совпадению с триграммами
SELECT
    title,
    similarity(title, 'полно') as sim
FROM articles
WHERE similarity(title, 'полно') > 0.1
ORDER BY sim DESC;

-- Тест 3: Поиск фразы (через оператор &)
SELECT title
FROM articles
WHERE to_tsvector('russian', content) @@
      to_tsquery('russian', 'полнотекстовый & поиск');


-- Базовый полнотекстовый поиск
EXPLAIN ANALYZE
SELECT
    article_id,
    title,
    content,
    ts_rank(to_tsvector('russian', title || ' ' || content),
            to_tsquery('russian', 'поиск & индексов')) AS relevance
FROM articles
WHERE to_tsvector('russian', title || ' ' || content) @@
      to_tsquery('russian', 'поиск & индексов')
ORDER BY relevance DESC;

-- https://explain.tensor.ru/archive/explain/153246a1a8448b6b1fce35a6ee43b610:0:2026-04-06
