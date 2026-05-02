CREATE TABLE Customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE Products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    stock_quantity INT DEFAULT 0
);

CREATE TABLE Orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES Customers(customer_id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'Pending'
);

CREATE TABLE OrderItems (
    order_item_id SERIAL PRIMARY KEY,
    order_id INT REFERENCES Orders(order_id) ON DELETE CASCADE,
    product_id INT REFERENCES Products(product_id),
    quantity INT NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL
);

-- Триггерлерге арналған қосымша кесте
CREATE TABLE Price_Logs (
    log_id SERIAL PRIMARY KEY,
    product_id INT,
    old_price NUMERIC,
    new_price NUMERIC,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- Тестілеу үшін бастапқы деректер (Mock data) енгізу
INSERT INTO Customers (first_name, last_name, email) VALUES
('Асқар', 'Мақсатұлы', 'askar@example.com'),
('Аяжан', 'Ерланқызы', 'ayazhan@example.com');

INSERT INTO Products (product_name, price, stock_quantity) VALUES
('Ноутбук ASUS ROG', 650000.00, 15),
('Смартфон iPhone 15', 550000.00, 30),
('Сымсыз құлаққап AirPods Pro', 120000.00, 50);

INSERT INTO Orders (customer_id, status) VALUES (1, 'Completed'), (2, 'Pending');

INSERT INTO OrderItems (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 650000.00),
(1, 3, 1, 120000.00),
(2, 2, 2, 550000.00);



-- 1. Тауар қалдығын тексеру
CREATE OR REPLACE FUNCTION get_product_stock(p_id INT) RETURNS INT AS $$
DECLARE v_stock INT;
BEGIN SELECT stock_quantity INTO v_stock 
FROM Products WHERE product_id = p_id; RETURN v_stock; END;
$$ LANGUAGE plpgsql;

-- 2. Клиенттің жалпы шығынын есептеу
CREATE OR REPLACE FUNCTION get_total_spent(c_id INT) RETURNS NUMERIC AS $$
DECLARE total_spent NUMERIC;
BEGIN 
SELECT COALESCE(SUM(quantity  unit_price), 0) 
INTO total_spent FROM OrderItems oi
JOIN Orders o ON oi.order_id = o.order_id WHERE o.customer_id = c_id; 
RETURN total_spent; 
END;
$$ LANGUAGE plpgsql;

-- 3. Жеңілдік мөлшерін есептеу
CREATE OR REPLACE FUNCTION calculate_discount
(price NUMERIC, discount_percent INT) RETURNS NUMERIC AS $$
BEGIN RETURN price - (price  discount_percent  100); END;
$$ LANGUAGE plpgsql;

-- 4. Клиенттің тапсырыс санын алу
CREATE OR REPLACE FUNCTION count_customer_orders(c_id INT) RETURNS INT AS $$
DECLARE order_count INT;
BEGIN SELECT COUNT() INTO order_count FROM Orders WHERE customer_id = c_id; RETURN order_count; END;
$$ LANGUAGE plpgsql;




SELECT get_product_stock(1); -- Күтілетін нәтиже 20
SELECT get_total_spent(1); -- Күтілетін нәтиже 770000.00
SELECT calculate_discount(100000.00, 15); -- Күтілетін нәтиже 850000.00
SELECT count_customer_orders(2); -- Күтілетін нәтиже 1


-- 1. Жаңа клиент қосу (INSERT)
CREATE OR REPLACE PROCEDURE add_new_customer
(p_first_name VARCHAR, p_last_name VARCHAR, p_email VARCHAR)
LANGUAGE plpgsql AS $$
BEGIN INSERT INTO Customers(first_name, last_name, email)
VALUES (p_first_name, p_last_name, p_email); END;
$$;

-- 2. Қоймадағы тауарды жаңарту (UPDATE)
CREATE OR REPLACE PROCEDURE update_inventory
(p_id INT, added_quantity INT)
LANGUAGE plpgsql AS $$
BEGIN UPDATE Products SET stock_quantity = stock_quantity + added_quantity
WHERE product_id = p_id; END;
$$;

-- 3. Тапсырыс статусын өзгерту (UPDATE)
CREATE OR REPLACE PROCEDURE update_order_status(o_id INT, new_status VARCHAR)
LANGUAGE plpgsql AS $$
BEGIN UPDATE Orders SET status = new_status WHERE order_id = o_id; END;
$$;

-- 4. Тапсырысты жою (DELETE)
CREATE OR REPLACE PROCEDURE delete_order(o_id INT)
LANGUAGE plpgsql AS $$
BEGIN DELETE FROM Orders WHERE order_id = o_id; END;
$$;



-- 1-тест Жаңа клиент қосу
CALL add_new_customer('Данияр', 'Асылбекұлы', 'daniyar@example.com');
SELECT  FROM Customers WHERE email = 'daniyar@example.com';

-- 2-тест 1-ші тауарға 5 дана қосу
CALL update_inventory(1, 5);
SELECT stock_quantity FROM Products WHERE product_id = 1; -- 20-тен 25-ға өсуі керек

-- 3-тест Тапсырыс статусын өзгерту
CALL update_order_status(2, 'Shipped');
SELECT status FROM Orders WHERE order_id = 2;

-- 4-тест Тапсырысты өшіру (CASCADE арқылы OrderItems-тағы мәлімет те өшеді)
-- Қауіпсіздік үшін алдымен жаңа тапсырыс жасап, соны өшіреміз
INSERT INTO Orders (order_id, customer_id, status) VALUES (99, 1, 'Canceled');
CALL delete_order(99);




CREATE OR REPLACE FUNCTION log_price_change() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.price  OLD.price THEN
        INSERT INTO Price_Logs(product_id, old_price, new_price) VALUES (OLD.product_id, OLD.price, NEW.price);
    END IF; RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_price_change AFTER UPDATE ON Products FOR EACH ROW EXECUTE FUNCTION log_price_change();

-- ТЕСТІЛЕУ
UPDATE Products SET price = 600000.00 WHERE product_id = 1;
SELECT  FROM Price_Logs; -- Лог кестесін тексеру 



CREATE OR REPLACE FUNCTION notify_mass_delete() RETURNS TRIGGER AS $$
BEGIN RAISE NOTICE 'Тапсырыстар кестесінен мәлімет өшірілді (Statement Level Trigger)'; 
RETURN NULL; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_statement_delete AFTER DELETE ON 
Orders FOR EACH STATEMENT EXECUTE FUNCTION notify_mass_delete();

-- ТЕСТІЛЕУ
DELETE FROM Orders WHERE status = 'Canceled'; -- Хабарлама шығуын қадағалау 



CREATE VIEW Customer_Order_View AS SELECT c.first_name, c.email, o.order_date 
FROM Customers c JOIN Orders o ON c.customer_id = o.customer_id;

CREATE OR REPLACE FUNCTION insert_instead_of_view() RETURNS TRIGGER AS $$
DECLARE new_cust_id INT;
BEGIN
    INSERT INTO Customers (first_name, email) VALUES (NEW.first_name, NEW.email) ON CONFLICT (email)
	DO NOTHING RETURNING customer_id INTO new_cust_id;
    IF new_cust_id IS NULL THEN SELECT customer_id INTO new_cust_id FROM Customers WHERE email = NEW.email; END IF;
    INSERT INTO Orders (customer_id, order_date) VALUES (new_cust_id, CURRENT_TIMESTAMP);
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_instead_of_insert INSTEAD OF INSERT ON Customer_Order_View 
FOR EACH ROW EXECUTE FUNCTION insert_instead_of_view();


-- ТЕСТІЛЕУ
INSERT INTO Customer_Order_View (first_name, email) VALUES ('Мадина', 'madina@example.com');
SELECT  FROM Customers WHERE email = 'madina@example.com'; -- Клиент кестеге түскенін тексеру 



BEGIN; -- Транзакция бастау [cite 28]
INSERT INTO Orders (customer_id, status) VALUES (1, 'Processing');
SAVEPOINT sp_success; -- Сақтау нүктесі 
UPDATE Products SET stock_quantity = stock_quantity - 1 WHERE product_id = 3;
COMMIT; -- Транзакцияны бекіту


BEGIN; 
INSERT INTO Orders (customer_id, status) VALUES (2, 'Pending');
SAVEPOINT sp_before_payment; -- Сақтау нүктесі 
-- Тауар санын азайтамыз
UPDATE Products SET stock_quantity = stock_quantity - 500 WHERE product_id = 2;
-- Осы жерде қателік кетті делік (мысалы, қалдық теріс болып кетті), сондықтан кері қайтарамыз
ROLLBACK TO sp_before_payment; -- Өзгерісті кері қайтару 

COMMIT;