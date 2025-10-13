/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Тулайкин Максим Геннадьевич 
 * Дата: 01.04.2025
*/

-- Пример фильтрации данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_ads AS (
    SELECT
        a.id,
        COALESCE(a.days_exposition, 1) AS days_exposition, -- NULL заменяем на 1 (активные объявления)
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        c.city,
        t.type
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    JOIN real_estate.type t ON f.type_id = t.type_id
    JOIN limits l ON TRUE
    WHERE f.total_area < l.total_area_limit
      AND (f.rooms < l.rooms_limit OR f.rooms IS NULL)
      AND (f.balcony < l.balcony_limit OR f.balcony IS NULL)
      AND ((f.ceiling_height < l.ceiling_height_limit_h
           AND f.ceiling_height > l.ceiling_height_limit_l) OR f.ceiling_height IS NULL)
      AND (c.city = 'Санкт-Петербург' OR t.type = 'город')
),
categorized_ads AS (
    SELECT
        CASE
            WHEN days_exposition = 1 THEN 'Активные'
            WHEN days_exposition <= 7 THEN '0-7 дней'
            WHEN days_exposition <= 30 THEN '8-30 дней'
            WHEN days_exposition <= 90 THEN '31-90 дней'
            WHEN days_exposition <= 180 THEN '91-180 дней'
            ELSE 'более 180 дней'
        END AS exposition_category,
        CASE 
            WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'Ленинградская область'
        END AS location,
        COUNT(*) AS ads_count,
        ROUND(AVG(last_price / NULLIF(total_area, 0))::numeric, 2) AS avg_price_per_sqm,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
        ROUND(AVG(rooms)::numeric, 2) AS avg_rooms,
        ROUND(AVG(balcony)::numeric, 2) AS avg_balcony
    FROM filtered_ads
    GROUP BY exposition_category, location
)
SELECT
    exposition_category,
    location,
    ads_count,
    avg_price_per_sqm,
    avg_total_area,
    avg_rooms,
    avg_balcony,
    ROUND(ads_count * 100.0 / SUM(ads_count) OVER (PARTITION BY location), 2) AS percentage_of_volume
FROM categorized_ads
ORDER BY 
    CASE exposition_category
        WHEN 'Активные' THEN 0
        WHEN '0-7 дней' THEN 1
        WHEN '8-30 дней' THEN 2
        WHEN '31-90 дней' THEN 3
        WHEN '91-180 дней' THEN 4
        ELSE 5
    END,
    location;


-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_data AS (
    SELECT
        EXTRACT(MONTH FROM a.first_day_exposition) AS month,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        c.city,
        t.type,
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'Ленинградская область'
        END AS region
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    JOIN real_estate.type t ON f.type_id = t.type_id
    JOIN limits l ON TRUE
    WHERE f.total_area < l.total_area_limit
      AND (f.rooms < l.rooms_limit OR f.rooms IS NULL)
      AND (f.balcony < l.balcony_limit OR f.balcony IS NULL)
      AND ((f.ceiling_height < l.ceiling_height_limit_h
           AND f.ceiling_height > l.ceiling_height_limit_l) OR f.ceiling_height IS NULL)
      AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
      AND (c.city = 'Санкт-Петербург' OR t.type = 'город')
)
SELECT
    month,
    region,
    COUNT(*) AS total_ads,
    ROUND(AVG(days_exposition)::numeric, 1) AS avg_days_on_market,
    ROUND(AVG(last_price / NULLIF(total_area, 0))::numeric, 2) AS avg_price_per_sqm,
    ROUND(AVG(total_area)::numeric, 2) AS avg_area,
    ROUND(AVG(rooms)::numeric, 1) AS avg_rooms
FROM filtered_data
GROUP BY month, region
ORDER BY region, month;


-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_ads AS (
    SELECT
        a.id,
        a.days_exposition,
        a.first_day_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        c.city,
        t.type AS settlement_type,
        CASE WHEN a.days_exposition IS NOT NULL THEN 1 ELSE 0 END AS was_removed
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    JOIN real_estate.type t ON f.type_id = t.type_id
    JOIN limits l ON TRUE
    WHERE c.city <> 'Санкт-Петербург'
      AND f.total_area < l.total_area_limit
      AND (f.rooms < l.rooms_limit OR f.rooms IS NULL)
      AND (f.balcony < l.balcony_limit OR f.balcony IS NULL)
      AND ((f.ceiling_height < l.ceiling_height_limit_h
           AND f.ceiling_height > l.ceiling_height_limit_l) OR f.ceiling_height IS NULL)
),
settlement_stats AS (
    SELECT
        city AS settlement_name,
        settlement_type,
        COUNT(*) AS publications_count,
        SUM(was_removed) AS removed_ads,
        ROUND((SUM(was_removed) * 100.0 / COUNT(*)), 1) AS withdrawal_percentage,
        ROUND(AVG(days_exposition)) AS avg_days_active,
        ROUND(AVG(last_price / NULLIF(total_area, 0))) AS avg_price_sqm,
        ROUND(AVG(total_area)) AS avg_area
    FROM filtered_ads
    GROUP BY city, settlement_type
    HAVING COUNT(*) > 50
),
ranked_settlements AS (
    SELECT
        *,
        NTILE(10) OVER (ORDER BY avg_days_active) AS activity_rank
    FROM settlement_stats
)
SELECT
    settlement_name AS "Населенный пункт",
    settlement_type AS "Тип населенного пункта",
    publications_count AS "Число публикаций",
    removed_ads AS "Число снятых",
    withdrawal_percentage AS "Доля снятия, %",
    avg_days_active AS "Ср. дней активности",
    avg_price_sqm AS "Ср. цена м², руб",
    avg_area AS "Ср. площадь, м²",
    activity_rank AS "Ранг активности"
FROM ranked_settlements
ORDER BY withdrawal_percentage DESC
LIMIT 15;