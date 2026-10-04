-- Demo furniture e-commerce warehouse: deterministic seed, intentionally NO table/column comments
-- so the Metabot "before" baseline has only raw names. Descriptions are applied by scripts/enrich-metadata.sh.
SELECT setseed(0.42);

CREATE TABLE dim_product (
    product_id    integer PRIMARY KEY,
    sku           text NOT NULL,
    product_name  text NOT NULL,
    category      text NOT NULL,
    subcategory   text NOT NULL,
    collection    text NOT NULL,
    list_price    numeric(10,2) NOT NULL
);

INSERT INTO dim_product VALUES
 (1,  'SOF-MEL-3S', 'Mellow 3-Seater Sofa',      'Living',  'Sofas',         'Mellow', 1899.00),
 (2,  'SOF-HAR-SC', 'Harper Sectional',          'Living',  'Sofas',         'Harper', 2599.00),
 (3,  'SOF-DUN-LV', 'Dune Loveseat',             'Living',  'Sofas',         'Dune',   1299.00),
 (4,  'BED-ARI-QN', 'Aria Queen Bed Frame',      'Bedroom', 'Beds',          'Aria',   1499.00),
 (5,  'BED-OSL-KG', 'Oslo King Platform Bed',    'Bedroom', 'Beds',          'Oslo',   1799.00),
 (6,  'DIN-NOV-TB', 'Nova Dining Table',         'Dining',  'Dining Tables', 'Nova',   1599.00),
 (7,  'DIN-ELM-CH', 'Elm Dining Chair',          'Dining',  'Dining Chairs', 'Elm',     249.00),
 (8,  'DIN-TER-RD', 'Terra Round Table',         'Dining',  'Dining Tables', 'Terra',  1199.00),
 (9,  'STO-HAV-SB', 'Haven Sideboard',           'Storage', 'Sideboards',    'Haven',  1399.00),
 (10, 'STO-LYR-BK', 'Lyra Bookshelf',            'Storage', 'Bookshelves',   'Lyra',    799.00),
 (11, 'LIV-ORB-CT', 'Orbit Coffee Table',        'Living',  'Coffee Tables', 'Orbit',   699.00),
 (12, 'OUT-PAL-LG', 'Palm Outdoor Lounge',       'Outdoor', 'Lounges',       'Palm',   2199.00),
 (13, 'OUT-COA-DS', 'Coast Outdoor Dining Set',  'Outdoor', 'Dining Sets',   'Coast',  2899.00),
 (14, 'BED-NOC-BT', 'Noce Bedside Table',        'Bedroom', 'Bedside Tables','Noce',    349.00),
 (15, 'DEC-LIN-PL', 'Linen Throw Pillow',        'Decor',   'Cushions',      'Linen',    49.00),
 (16, 'DEC-CER-VS', 'Ceramic Vase',              'Decor',   'Vases',         'Ceramic',  79.00);

CREATE TABLE dim_customer (
    customer_id          integer PRIMARY KEY,
    market               text NOT NULL,
    customer_type        text NOT NULL,
    acquisition_channel  text NOT NULL,
    first_seen_date      date NOT NULL
);

INSERT INTO dim_customer
SELECT g,
       (ARRAY['AU','AU','AU','AU','SG','SG','US','US','US','UK','CA'])[1 + floor(random() * 11)::int],
       CASE WHEN random() < 0.08 THEN 'B2B' ELSE 'B2C' END,
       (ARRAY['organic','paid_search','social','referral','email','showroom'])[1 + floor(random() * 6)::int],
       DATE '2024-06-01' + (random() * 600)::int
FROM generate_series(1, 3000) g;

CREATE TABLE fact_saleorder (
    order_id                 text PRIMARY KEY,
    market                   text NOT NULL,
    customer_id              integer NOT NULL REFERENCES dim_customer (customer_id),
    order_state              text NOT NULL,
    payment_status           text NOT NULL,
    created_at               timestamp NOT NULL,
    payment_completion_time  timestamp,
    o2o_flag                 char(1) NOT NULL,
    goods_amount             numeric(12,2),
    promo_amount             numeric(12,2),
    shipping_amount          numeric(12,2),
    tax_amount               numeric(12,2),
    order_amount             numeric(12,2),
    reporting_sales          numeric(12,2)
);

INSERT INTO fact_saleorder (order_id, market, customer_id, order_state, payment_status,
                            created_at, payment_completion_time, o2o_flag)
SELECT c.market || '-' || (100000 + o.n),
       c.market,
       o.customer_id,
       CASE WHEN o.r < 0.03 THEN 'cart' WHEN o.r < 0.09 THEN 'canceled' ELSE 'complete' END,
       CASE WHEN o.r < 0.03 THEN 'pending' WHEN o.r < 0.09 THEN 'voided' ELSE 'paid' END,
       o.created_at,
       CASE WHEN o.r >= 0.09 THEN o.created_at + random() * interval '2 hours' END,
       CASE WHEN c.market <> 'CA' AND random() < 0.10 THEN 'Y' ELSE 'N' END
FROM (
    SELECT g AS n,
           1 + floor(random() * 3000)::int AS customer_id,
           TIMESTAMP '2025-01-01' + random() * (TIMESTAMP '2026-09-30' - TIMESTAMP '2025-01-01') AS created_at,
           random() AS r
    FROM generate_series(1, 12000) g
) o
JOIN dim_customer c USING (customer_id);

CREATE TABLE fact_saleorderline (
    line_id           serial PRIMARY KEY,
    order_id          text NOT NULL REFERENCES fact_saleorder (order_id),
    product_id        integer NOT NULL REFERENCES dim_product (product_id),
    quantity          integer NOT NULL,
    list_price        numeric(10,2) NOT NULL,
    promo_amount      numeric(12,2) NOT NULL,
    discounted_amount numeric(12,2) NOT NULL,
    is_gwp            boolean NOT NULL,
    foc_flag          char(1) NOT NULL
);

WITH order_lines AS MATERIALIZED (
    SELECT order_id, 1 + floor(random() * 3)::int AS n_lines
    FROM fact_saleorder
),
raw AS (
    SELECT ol.order_id,
           1 + floor(random() * 14)::int AS product_id,
           1 + floor(random() * 2)::int  AS quantity,
           (ARRAY[0, 0, 0, 0.10, 0.15, 0.20])[1 + floor(random() * 6)::int] AS disc
    FROM order_lines ol
    JOIN generate_series(1, 3) k ON k <= ol.n_lines
)
INSERT INTO fact_saleorderline (order_id, product_id, quantity, list_price, promo_amount,
                                discounted_amount, is_gwp, foc_flag)
SELECT r.order_id, r.product_id, r.quantity, p.list_price,
       round(r.quantity * p.list_price * r.disc, 2),
       round(r.quantity * p.list_price * (1 - r.disc), 2),
       false, 'N'
FROM raw r
JOIN dim_product p USING (product_id);

-- Gift-with-purchase lines: free decor items on ~5% of non-cart orders.
INSERT INTO fact_saleorderline (order_id, product_id, quantity, list_price, promo_amount,
                                discounted_amount, is_gwp, foc_flag)
SELECT g.order_id, g.pid, 1, p.list_price, p.list_price, 0, true, 'Y'
FROM (
    SELECT order_id, 15 + floor(random() * 2)::int AS pid
    FROM fact_saleorder
    WHERE order_state <> 'cart' AND random() < 0.05
) g
JOIN dim_product p ON p.product_id = g.pid;

UPDATE fact_saleorder o
SET goods_amount = s.goods,
    promo_amount = s.promo
FROM (
    SELECT order_id, sum(discounted_amount) AS goods, sum(promo_amount) AS promo
    FROM fact_saleorderline
    GROUP BY order_id
) s
WHERE s.order_id = o.order_id;

-- Carts carry no shipping or tax, mirroring how the real order system stores carts.
UPDATE fact_saleorder
SET shipping_amount = CASE WHEN order_state = 'cart' THEN 0
                           WHEN goods_amount > 1500 THEN 0
                           ELSE round((49 + random() * 100)::numeric, 2) END,
    tax_amount = CASE WHEN order_state = 'cart' THEN 0
                      ELSE round(goods_amount * CASE market WHEN 'AU' THEN 0.10 WHEN 'SG' THEN 0.09
                                                            WHEN 'US' THEN 0.07 WHEN 'UK' THEN 0.20
                                                            ELSE 0.13 END, 2) END;

UPDATE fact_saleorder
SET order_amount    = goods_amount + shipping_amount + tax_amount,
    reporting_sales = goods_amount + shipping_amount;

CREATE TABLE fact_saleorder_shipment (
    shipment_id   serial PRIMARY KEY,
    order_id      text NOT NULL REFERENCES fact_saleorder (order_id),
    state         text NOT NULL,
    service_type  text NOT NULL,
    shipment_fee  numeric(12,2) NOT NULL,
    shipped_at    timestamp,
    delivered_at  timestamp
);

INSERT INTO fact_saleorder_shipment (order_id, state, service_type, shipment_fee, shipped_at, delivered_at)
SELECT s.order_id,
       s.state,
       s.service_type,
       s.shipment_fee,
       CASE WHEN s.state <> 'ready' THEN s.shipped_at END,
       CASE WHEN s.state = 'delivered' THEN s.shipped_at + (3 + random() * 11) * interval '1 day' END
FROM (
    SELECT o.order_id,
           CASE WHEN o.created_at < TIMESTAMP '2026-09-05' THEN 'delivered'
                WHEN o.created_at < TIMESTAMP '2026-09-20' THEN 'shipped'
                ELSE 'ready' END AS state,
           (ARRAY['Standard','Standard','Room of Choice','White Glove'])[1 + floor(random() * 4)::int] AS service_type,
           o.shipping_amount AS shipment_fee,
           o.payment_completion_time + (2 + random() * 5) * interval '1 day' AS shipped_at
    FROM fact_saleorder o
    WHERE o.order_state = 'complete'
) s;

CREATE INDEX ON fact_saleorder (market);
CREATE INDEX ON fact_saleorder (created_at);
CREATE INDEX ON fact_saleorderline (order_id);
CREATE INDEX ON fact_saleorder_shipment (order_id);

-- Read-only role for Metabase: Metabot-generated SQL can never write.
CREATE ROLE metabase_ro LOGIN PASSWORD 'metabase_ro';
GRANT CONNECT ON DATABASE analytics TO metabase_ro;
GRANT USAGE ON SCHEMA public TO metabase_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO metabase_ro;
