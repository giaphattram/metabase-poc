-- Ground truth for the Metabot test questions (README). Run: scripts/ground-truth.sh
-- Data spans 2025-01-01 to 2026-09-30, so "last month" means September 2026.

-- Q1 "What were total sales in AU last month?"
-- Trap: sales = reporting_sales on complete orders only (not order_amount, not carts/canceled).
SELECT round(sum(reporting_sales), 2) AS au_sales_sep_2026
FROM fact_saleorder
WHERE market = 'AU' AND order_state = 'complete'
  AND created_at >= '2026-09-01' AND created_at < '2026-10-01';

-- Q2 "What is our AOV by market?"
-- Trap: glossary term AOV; must exclude carts and canceled orders.
SELECT market, round(avg(reporting_sales), 2) AS aov
FROM fact_saleorder
WHERE order_state = 'complete'
GROUP BY market ORDER BY market;

-- Q3 "How many carts did we have in 2026?"
-- Trap: "cart" is an order_state value, not a table.
SELECT count(*) AS carts_2026
FROM fact_saleorder
WHERE order_state = 'cart' AND created_at >= '2026-01-01';

-- Q4 "Which product category makes the most revenue?"
-- Trap: needs a 3-table join and complete orders; discounted_amount is revenue, not the discount.
SELECT p.category, round(sum(l.discounted_amount), 2) AS revenue
FROM fact_saleorderline l
JOIN fact_saleorder o USING (order_id)
JOIN dim_product p USING (product_id)
WHERE o.order_state = 'complete'
GROUP BY p.category ORDER BY revenue DESC;

-- Q5 "What's the average delivery lead time by service type?"
-- Trap: glossary term; only delivered shipments; result in days.
SELECT service_type,
       round(avg(extract(epoch FROM delivered_at - shipped_at) / 86400)::numeric, 1) AS avg_days
FROM fact_saleorder_shipment
WHERE state = 'delivered'
GROUP BY service_type ORDER BY service_type;

-- Q6 "How many gift-with-purchase items did we give away?"
-- Trap: GWP is the flag is_gwp; count units on complete orders only.
SELECT sum(l.quantity) AS gwp_units
FROM fact_saleorderline l
JOIN fact_saleorder o USING (order_id)
WHERE l.is_gwp AND o.order_state = 'complete';

-- Q7 "What share of orders are O2O in each market?"
-- Trap: glossary term O2O (o2o_flag = 'Y'); complete orders; CA should be 0%.
SELECT market,
       round(100.0 * count(*) FILTER (WHERE o2o_flag = 'Y') / count(*), 1) AS o2o_pct
FROM fact_saleorder
WHERE order_state = 'complete'
GROUP BY market ORDER BY market;

-- Q8 "Top 5 products by units sold"
-- Trap: exclude free gift lines and incomplete orders, or the decor gifts inflate the ranking.
SELECT p.product_name, sum(l.quantity) AS units
FROM fact_saleorderline l
JOIN fact_saleorder o USING (order_id)
JOIN dim_product p USING (product_id)
WHERE o.order_state = 'complete' AND NOT l.is_gwp
GROUP BY p.product_name ORDER BY units DESC LIMIT 5;
