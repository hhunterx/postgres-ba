-- ============================================================================
-- PostgreSQL Drop-in Replacement - Test Schema Initialization
-- ============================================================================
-- This script runs automatically on first container startup
-- It demonstrates compatibility with postgres:18-alpine

-- Create a test table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create another test table
CREATE TABLE posts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    content TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
INSERT INTO users (username, email) VALUES
    ('alice', 'alice@example.com'),
    ('bob', 'bob@example.com'),
    ('charlie', 'charlie@example.com');

INSERT INTO posts (user_id, title, content) VALUES
    (1, 'First Post', 'Hello, this is Alice''s first post!'),
    (1, 'Second Post', 'Another post from Alice'),
    (2, 'Bob''s Post', 'Hello from Bob!'),
    (3, 'Charlie''s Post', 'Greetings from Charlie!');

-- Create a view
CREATE VIEW user_post_count AS
SELECT 
    u.id,
    u.username,
    u.email,
    COUNT(p.id) as post_count
FROM users u
LEFT JOIN posts p ON u.id = p.user_id
GROUP BY u.id, u.username, u.email;

-- Create a function
CREATE OR REPLACE FUNCTION get_user_posts(p_username VARCHAR)
RETURNS TABLE (
    post_id INTEGER,
    title VARCHAR,
    created_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT p.id, p.title, p.created_at
    FROM posts p
    JOIN users u ON p.user_id = u.id
    WHERE u.username = p_username
    ORDER BY p.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Create indexes for better performance
CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);

-- Log initialization
SELECT 'PostgreSQL compatible initialization completed!' as status;
