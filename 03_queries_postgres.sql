-- ============================================================
-- Файл 3/5: 10 аналитических запросов (PostgreSQL)
-- Все суммы считаются только по доставленным заказам (delivered)
-- ============================================================

-- 1. ТОП-10 товаров по выручке
SELECT p.product_id,
       p.name                       AS product,
       p.category,
       ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2)  AS revenue,
       SUM(oi.quantity)             AS units_sold
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN orders o   ON o.order_id   = oi.order_id
WHERE o.status = 'delivered'
GROUP BY p.product_id, p.name, p.category
ORDER BY revenue DESC
LIMIT 10;

-- 2. Динамика выручки по месяцам (LAG - месяц к месяцу)
WITH monthly AS (
    SELECT date_trunc('month', o.order_date)::date AS month,
           ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY 1
)
SELECT month,
       revenue,
       LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
       ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month) * 100, 1) AS growth_pct
FROM monthly
ORDER BY month;

-- 3. Сегментация клиентов по сумме покупок (упрощённый RFM)
WITH cust_stats AS (
    SELECT o.customer_id,
           COUNT(*)                                             AS orders_cnt,
           ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2)  AS total_spent,
           MAX(o.order_date)                                    AS last_order,
           DATE '2025-06-30' - MAX(o.order_date)                AS days_since_last
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
)
SELECT customer_id,
       orders_cnt,
       total_spent,
       last_order,
       days_since_last,
       CASE WHEN total_spent >= 100000 THEN 'VIP'
            WHEN total_spent >=  30000 THEN 'Постоянный'
            WHEN total_spent >=  10000 THEN 'Развивающийся'
            ELSE 'Новичок'
       END AS segment
FROM cust_stats
ORDER BY total_spent DESC;

-- 4. Доля отменённых заказов по месяцам
SELECT date_trunc('month', o.order_date)::date AS month,
       COUNT(*) AS orders_total,
       COUNT(*) FILTER (WHERE o.status = 'cancelled') AS cancelled,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.status = 'cancelled') / COUNT(*), 1) AS cancel_pct
FROM orders o
GROUP BY 1
ORDER BY 1;

-- 5. Средний чек по городам
SELECT c.city,
       COUNT(DISTINCT o.order_id) AS orders_cnt,
       ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2) AS revenue,
       ROUND(AVG(o_total.total)::numeric, 2) AS avg_order_value
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN LATERAL (
    SELECT SUM(oi.quantity * oi.unit_price) AS total
    FROM order_items oi
    WHERE oi.order_id = o.order_id
) o_total ON TRUE
WHERE o.status = 'delivered'
GROUP BY c.city
ORDER BY avg_order_value DESC;

-- 6. Доля повторных покупателей
WITH buyer_orders AS (
    SELECT o.customer_id,
           COUNT(DISTINCT o.order_id) AS orders_cnt
    FROM orders o
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
)
SELECT COUNT(*)                                            AS buyers_total,
       COUNT(*) FILTER (WHERE orders_cnt > 1)              AS repeat_buyers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE orders_cnt > 1) / COUNT(*), 1) AS retention_pct
FROM buyer_orders;

-- 7. Выручка категорий и их доля в общей выручке
SELECT p.category,
       ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2) AS revenue,
       ROUND(100.0 * SUM(oi.quantity * oi.unit_price)
             / SUM(SUM(oi.quantity * oi.unit_price)) OVER (), 1) AS revenue_share_pct
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN orders o   ON o.order_id   = oi.order_id
WHERE o.status = 'delivered'
GROUP BY p.category
ORDER BY revenue DESC;

-- 8. Товары, которые чаще всего покупают вместе
SELECT a.product_id AS product_a,
       pa.name      AS product_a_name,
       b.product_id AS product_b,
       pb.name      AS product_b_name,
       COUNT(*)     AS times_together
FROM order_items a
JOIN order_items b ON b.order_id = a.order_id AND b.product_id > a.product_id
JOIN products pa   ON pa.product_id = a.product_id
JOIN products pb   ON pb.product_id = b.product_id
GROUP BY a.product_id, pa.name, b.product_id, pb.name
HAVING COUNT(*) >= 2
ORDER BY times_together DESC
LIMIT 10;

-- 9. «Спящие» клиенты: не покупали дольше 90 дней
WITH last_orders AS (
    SELECT o.customer_id,
           MAX(o.order_date) AS last_order
    FROM orders o
    WHERE o.status = 'delivered'
    GROUP BY o.customer_id
)
SELECT c.customer_id,
       c.name,
       c.email,
       c.city,
       lo.last_order,
       DATE '2025-06-30' - lo.last_order AS days_since_last
FROM customers c
JOIN last_orders lo ON lo.customer_id = c.customer_id
WHERE lo.last_order < DATE '2025-06-30' - INTERVAL '90 days'
ORDER BY days_since_last DESC;

-- 10. Средний чек (AOV) по месяцам
SELECT date_trunc('month', o.order_date)::date AS month,
       ROUND(SUM(oi.quantity * oi.unit_price)::numeric, 2)                AS revenue,
       COUNT(DISTINCT o.order_id)                                         AS orders_cnt,
       ROUND(SUM(oi.quantity * oi.unit_price)
             / COUNT(DISTINCT o.order_id)::numeric, 2)                    AS avg_order_value
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'delivered'
GROUP BY 1
ORDER BY 1;
