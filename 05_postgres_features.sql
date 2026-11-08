-- ============================================================
-- Файл 5/5: возможности, которые есть только в PostgreSQL
-- (в MySQL/SQLite их нет или реализация другая)
-- ============================================================

-- 1. DISTINCT ON: первый заказ каждого клиента.
--    Нестандартное расширение Postgres - часто спрашивают на собеседованиях.
SELECT DISTINCT ON (customer_id)
       customer_id,
       order_id,
       order_date
FROM orders
WHERE status = 'delivered'
ORDER BY customer_id, order_date;

-- 2. FILTER: условные агрегаты в одном проходе таблицы.
--    Заменяет и COUNT(CASE WHEN ...), и лишние подзапросы.
SELECT c.city,
       COUNT(*)                                                    AS orders_total,
       COUNT(*) FILTER (WHERE o.status = 'delivered')              AS delivered_cnt,
       COUNT(*) FILTER (WHERE o.status = 'in_transit')             AS in_transit_cnt,
       COUNT(*) FILTER (WHERE o.status = 'cancelled')              AS cancelled_cnt,
       ROUND(SUM(oi.quantity * oi.unit_price)
             FILTER (WHERE o.status = 'delivered')::numeric, 2)    AS delivered_revenue
FROM orders o
JOIN customers c    ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id   = o.order_id
GROUP BY c.city
ORDER BY delivered_revenue DESC;

-- 3. generate_series: «скелет» месяцев, включая те, где выручки не было.
--    LEFT JOIN с фактами дает нули там, где GROUP BY честно молчал бы.
WITH months AS (
    SELECT generate_series(DATE '2023-01-01',
                           DATE '2025-06-01',
                           INTERVAL '1 month')::date AS month
),
revenue AS (
    SELECT date_trunc('month', o.order_date)::date AS month,
           SUM(oi.quantity * oi.unit_price) AS rev
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY 1
)
SELECT m.month,
       ROUND(COALESCE(r.rev, 0)::numeric, 2) AS revenue,
       CASE WHEN r.rev IS NULL THEN 'нет выручки' END AS note
FROM months m
LEFT JOIN revenue r ON r.month = m.month
ORDER BY m.month;

-- 4. GROUPING SETS: несколько уровней агрегации одним запросом
--    (итоги по категориям + общий итог; без GROUPING SETS пришлось бы
--    писать UNION ALL из двух запросов).
SELECT COALESCE(p.category, 'ИТОГО') AS category,
       ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2) AS revenue,
       COUNT(*)                                            AS items_sold
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN orders o   ON o.order_id   = oi.order_id
WHERE o.status = 'delivered'
GROUP BY GROUPING SETS ((p.category), ());

-- 5. Интервальная арифметика: клиенты без покупок дольше 90 дней.
--    DATE - INTERVAL возвращает дату, никаких ручных вычислений.
SELECT c.customer_id,
       c.name,
       c.email,
       MAX(o.order_date) AS last_order
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
WHERE o.status = 'delivered'
GROUP BY c.customer_id, c.name, c.email
HAVING MAX(o.order_date) < DATE '2025-06-30' - INTERVAL '90 days'
ORDER BY last_order;
