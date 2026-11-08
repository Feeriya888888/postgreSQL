-- ============================================================
-- Файл 4/5: 10 запросов на оконных функциях (PostgreSQL)
-- Оконные функции НЕ схлопывают строки в группы, как GROUP BY,
-- а добавляют к каждой строке вычисление по «окну» строк.
-- ============================================================

-- 1. Топ-3 товара в каждой категории (классическая задача n-th per group)
WITH ranked AS (
    SELECT p.category,
           p.name AS product,
           ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2) AS revenue,
           ROW_NUMBER() OVER (
               PARTITION BY p.category
               ORDER BY SUM(oi.quantity * oi.unit_price) DESC
           ) AS rn
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    JOIN orders o   ON o.order_id   = oi.order_id
    WHERE o.status = 'delivered'
    GROUP BY p.category, p.name, p.product_id
)
SELECT category, product, revenue
FROM ranked
WHERE rn <= 3
ORDER BY category, rn;

-- 2. RANK vs DENSE_RANK: разница видна на ничьих
WITH cust_sums AS (
    SELECT o.customer_id,
           ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2) AS total_spent
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
)
SELECT customer_id,
       total_spent,
       RANK()       OVER (ORDER BY total_spent DESC) AS rank_pos,
       DENSE_RANK() OVER (ORDER BY total_spent DESC) AS dense_rank_pos
FROM cust_sums
ORDER BY dense_rank_pos
LIMIT 25;

-- 3. LAG / LEAD: интервал между заказами клиента.
-- Именованное окно (WINDOW w) избавляет от копирования OVER(...) трижды.
SELECT o.order_id,
       o.customer_id,
       o.order_date,
       LAG(o.order_date) OVER w AS prev_order_date,
       LEAD(o.order_date) OVER w AS next_order_date,
       o.order_date - LAG(o.order_date) OVER w AS days_since_prev
FROM orders o
WHERE o.status = 'delivered'
WINDOW w AS (PARTITION BY o.customer_id ORDER BY o.order_date)
ORDER BY o.customer_id, o.order_date;

-- 4. NTILE(4): разбиваем клиентов на квартили по сумме покупок
WITH cust_sums AS (
    SELECT o.customer_id,
           ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2) AS total_spent
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
)
SELECT customer_id,
       total_spent,
       NTILE(4) OVER (ORDER BY total_spent DESC) AS quartile
FROM cust_sums
ORDER BY quartile, total_spent DESC;

-- 5. Накопленная выручка (running total)
WITH monthly AS (
    SELECT date_trunc('month', o.order_date)::date AS month,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY 1
)
SELECT month,
       ROUND(revenue::numeric, 2) AS revenue,
       ROUND(SUM(revenue) OVER (ORDER BY month)::numeric, 2) AS running_total
FROM monthly
ORDER BY month;

-- 6. Скользящее среднее за 3 месяца.
-- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW = текущий + 2 предыдущих.
WITH monthly AS (
    SELECT date_trunc('month', o.order_date)::date AS month,
           SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY 1
)
SELECT month,
       ROUND(revenue::numeric, 2) AS revenue,
       ROUND(AVG(revenue) OVER (ORDER BY month
               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)::numeric, 2) AS moving_avg_3m
FROM monthly
ORDER BY month;

-- 7. Агрегат «рядом со строкой»: количество и сумма заказов клиента
--    в каждой строке заказа, без схлопывания в один ряд на клиента.
--    Сначала GROUP BY по заказам в CTE, оконные функции - поверх.
WITH order_totals AS (
    SELECT o.order_id,
           o.customer_id,
           o.order_date,
           SUM(oi.quantity * oi.unit_price) AS order_total
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.order_id, o.customer_id, o.order_date
)
SELECT order_id,
       customer_id,
       order_date,
       ROUND(order_total::numeric, 2)                                          AS order_total,
       COUNT(*)      OVER (PARTITION BY customer_id)                           AS cust_orders_cnt,
       ROUND(SUM(order_total) OVER (PARTITION BY customer_id)::numeric, 2)     AS cust_total_spent
FROM order_totals
ORDER BY customer_id, order_date, order_id;

-- 8. FIRST_VALUE / LAST_VALUE: первый и последний заказ клиента.
-- Важно: без ROWS BETWEEN UNBOUNDED ... LAST_VALUE по умолчанию смотрит
-- только до текущей строки - классическая ловушка.
SELECT DISTINCT
       customer_id,
       order_date,
       FIRST_VALUE(order_date) OVER w AS first_order,
       LAST_VALUE(order_date)  OVER w AS last_order
FROM orders
WHERE status = 'delivered'
WINDOW w AS (
    PARTITION BY customer_id
    ORDER BY order_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
ORDER BY customer_id, order_date;

-- 9. PERCENT_RANK / CUME_DIST: перцентильная позиция клиента
WITH cust_sums AS (
    SELECT o.customer_id,
           ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2) AS total_spent
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
)
SELECT customer_id,
       total_spent,
       ROUND(PERCENT_RANK() OVER (ORDER BY total_spent)::numeric, 4) AS percent_rank,
       ROUND(CUME_DIST()    OVER (ORDER BY total_spent)::numeric, 4) AS cume_dist
FROM cust_sums
ORDER BY total_spent;

-- 10. Доля клиента в общей выручке: SUM() OVER () как общий итог
WITH cust_sums AS (
    SELECT o.customer_id,
           SUM(oi.quantity * oi.unit_price) AS total_spent
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
)
SELECT customer_id,
       ROUND(total_spent::numeric, 2) AS total_spent,
       ROUND(100.0 * total_spent / SUM(total_spent) OVER (), 2) AS revenue_share_pct
FROM cust_sums
ORDER BY revenue_share_pct DESC;
