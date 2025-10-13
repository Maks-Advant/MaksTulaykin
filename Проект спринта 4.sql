/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Тулайкин Максим Геннадьевич
 * Дата: 13.03.2025
*/

-- Часть 1. Исследовательский анализ данных

-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT 
	COUNT(payer) AS total_players, -- Общее кол-во игроков
	COUNT(payer) FILTER (WHERE payer = 1) AS payer_players, -- Кол-во платящих игроков
	ROUND(COUNT(payer) FILTER (WHERE payer = 1) * 1.0 / COUNT(payer) * 100, 2) AS ratio_payer_players -- Доля платящих игроков
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT race,
	COUNT(payer) FILTER (WHERE payer = 1) AS payer_players, -- Кол-во платящих игроков
	COUNT(*) AS total_player, -- Общее кол-во игроков
	ROUND(COUNT(payer) FILTER (WHERE payer = 1) * 1.0 / COUNT(payer) * 100, 2) AS ratio_payer_race -- Доля платящих игроков в разрезе каждой расы
FROM fantasy.users AS u
JOIN fantasy.race AS r  -- Присоединяем талбицу fantasy.race для определиния расы
ON u.race_id = r.race_id
GROUP BY race -- Группируем по расе
ORDER BY payer_players DESC; -- Сортируем по кол-ву платящих игроков

-- Задача 2. Исследование внутриигровых покупок

-- 2.1. Статистические показатели по полю amount:
SELECT  COUNT(amount) AS total_amount, -- Общее кол-во покупок
		SUM(amount) AS sum_total_amount, -- Суммарная стоимость всех покупок
		MIN(amount) AS min_amount, -- Минимальная стоимось покупки
		MAX(amount) AS max_amount, -- Максимальная стоимость покупки
		ROUND(AVG(amount)::numeric, 2) AS avg_amount,-- Среднее значение стоимость покупки. (Округленное значение до двух знаков после запятой)
		ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount)::numeric, 2) AS median_amount, -- Медиана стоимости покупки. (Округленное значение до двух знаков после запятой)
		ROUND(STDDEV(amount)::numeric, 2) AS stddev_amount -- Стандартное отклонение стоимости покупки. (Округленное значение до двух знаков после запятой)
FROM fantasy.events
WHERE amount > 0; -- Исключаем покупки с нулевой стоимотью 

-- 2.2: Аномальные нулевые покупки:
WITH count_amount AS(
SELECT  COUNT(amount) AS total_amount, -- Общее количество покупок
		COUNT(amount) FILTER (WHERE amount = 0) AS zero_amount -- Количество покупок с нулевой стоимостью
FROM fantasy.events
)
SELECT  total_amount, zero_amount,
		ROUND(zero_amount * 1.0 / total_amount * 100, 2) AS zero_amount_ratio -- Доля покупок с нулевой стоимостью
FROM count_amount;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
WITH players_stats AS (
SELECT  u.id, u.payer,
		COUNT(e.transaction_id) AS transaction_count, -- Кол-во покупок для каждого игрока
		SUM(e.amount) AS total_amount -- Суммарная стоимость покупокдля каждого игрока
FROM fantasy.users AS u
LEFT JOIN fantasy.events AS e -- Используем LEFT JOIN, чтобы включить всех игроков, даже если у них нет покупок.
ON u.id=e.id
WHERE e.amount > 0 -- Ислючаем нулевые покупки
GROUP BY u.id, u.payer
)
SELECT 
		CASE
			WHEN payer = 1 THEN 'Платящие'
			ELSE 'Неплатящие'
		END AS player_group, -- Группа игроков (Платящие и Неплатящие)
		COUNT(id) AS total_players, -- Общее кол-во игроков
		ROUND(AVG(transaction_count), 2) AS avg_tracaction_player, -- Среднее кол-во покупок на игрока
		ROUND(AVG(total_amount)::numeric, 2) AS avg_amount_player -- Средняя суммарная стоимость покупок на игрока
FROM players_stats 
GROUP BY payer;

-- 2.4: Популярные эпические предметы:
WITH items_sales AS (
SELECT  i.item_code,
		i.game_items AS item_name,
		COUNT(e.transaction_id) AS total_sales, -- Общее кол-во продаж
		COUNT(DISTINCT  e.id) AS uqique_players -- Кол-во уникальных игроков, купивших предмет
FROM fantasy.items AS i
LEFT JOIN fantasy.events AS e -- Используется LEFT JOIN, чтобы включить все предметы, даже если у них нет продаж
ON i.item_code = e.item_code 
WHERE e.amount > 0 -- Исключаем нулевые покупки
GROUP BY i.item_code, i.game_items
),
totals_sales AS (
SELECT 
		SUM(total_sales) AS overall_sales -- Общее кол-во продаж всех предметов
FROM items_sales
)
SELECT  items_sales.item_name,
		items_sales.item_code,
		ROUND(items_sales.total_sales * 1.0 / totals_sales.overall_sales * 100, 2) AS sales_ratio, -- Доля продаж каждого предмета от общего количества продаж	
		ROUND(items_sales.uqique_players * 1.0 / (SELECT COUNT(DISTINCT id) FROM fantasy.events) * 100, 2) AS player_ratio -- Доля игроков, которые хотя бы раз покупали предмет	
FROM items_sales, 
	 totals_sales
ORDER BY player_ratio DESC; -- Сортировка по популярности среди игроков

-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
WITH total_players_by_race AS
 (SELECT r.race AS race_name, COUNT(u.id) AS total_players
  FROM fantasy.users u
  JOIN fantasy.race r ON u.race_id = r.race_id
  GROUP BY r.race),
     players_with_purchases AS
 (SELECT r.race AS race_name, COUNT(DISTINCT e.id) AS payer_players, COUNT(DISTINCT e.id) FILTER (WHERE u.payer = 1) AS paying_players
  FROM fantasy.events e
  JOIN fantasy.users u ON e.id = u.id
  JOIN fantasy.race r ON u.race_id = r.race_id
  WHERE e.amount > 0
  GROUP BY r.race),
     player_activity AS
 (SELECT r.race AS race_name, COUNT(e.transaction_id) AS total_purchases, SUM(e.amount) AS total_amount
  FROM fantasy.events e
  JOIN fantasy.users u ON e.id = u.id
  JOIN fantasy.race r ON u.race_id = r.race_id
  WHERE e.amount > 0
  GROUP BY r.race)
SELECT t.race_name, t.total_players, p.payer_players, ROUND(p.payer_players * 1.0 / t.total_players * 100, 2) AS players_with_purchases_ratio, ROUND(p.paying_players * 1.0 / p.payer_players * 100, 2) AS paying_players_ratio, ROUND(a.total_purchases * 1.0 / p.payer_players, 2) AS avg_purchases_per_player, ROUND((a.total_amount * 1.0 / a.total_purchases)::numeric, 2) AS avg_purchase_amount, ROUND((a.total_amount * 1.0 / p.payer_players)::numeric, 2) AS avg_total_amount_per_player
FROM total_players_by_race t
JOIN players_with_purchases p ON t.race_name = p.race_name
JOIN player_activity a ON t.race_name = a.race_name
ORDER BY t.race_name;
