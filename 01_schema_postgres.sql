-- ============================================================
-- Проект «Аналитика продаж интернет-магазина» (PostgreSQL)
-- Файл 1/5: схема базы данных
-- СУБД: PostgreSQL 13+
-- Запуск: psql -f 01_schema_postgres.sql
-- ============================================================

DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name              TEXT          NOT NULL,
    email             TEXT          NOT NULL UNIQUE,
    city              TEXT          NOT NULL,
    registration_date DATE          NOT NULL
);

CREATE TABLE products (
    product_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name              TEXT          NOT NULL,
    category          TEXT          NOT NULL,
    price             NUMERIC(10,2) NOT NULL CHECK (price > 0)
);

CREATE TABLE orders (
    order_id          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id       INT           NOT NULL REFERENCES customers (customer_id),
    order_date        DATE          NOT NULL,
    status            TEXT          NOT NULL CHECK (status IN ('delivered', 'in_transit', 'cancelled'))
);

CREATE TABLE order_items (
    item_id           INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id          INT           NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    product_id        INT           NOT NULL REFERENCES products (product_id),
    quantity          SMALLINT      NOT NULL CHECK (quantity > 0),
    unit_price        NUMERIC(10,2) NOT NULL CHECK (unit_price > 0)
);

-- Индексы под аналитические запросы
CREATE INDEX idx_orders_customer     ON orders (customer_id);
CREATE INDEX idx_orders_date         ON orders (order_date);
CREATE INDEX idx_orders_status       ON orders (status);
CREATE INDEX idx_items_order         ON order_items (order_id);
CREATE INDEX idx_items_product       ON order_items (product_id);

-- Денормализованная выручка заказа: Postgres умеет держать агрегат в индексе
CREATE INDEX idx_items_order_revenue ON order_items (order_id, (quantity * unit_price));

COMMENT ON TABLE  customers         IS 'Клиенты магазина';
COMMENT ON TABLE  orders            IS 'Заказы: delivered / in_transit / cancelled';
COMMENT ON COLUMN orders.status     IS 'delivered - доставлен, in_transit - в пути, cancelled - отменён';
