-- QUERY 1: OVERALL RIDE HEALTH CHECK -- How big is the cancellation problem?
-- Objective:
-- Before finding root causes, we first need to know how serious the problem
-- is. This query counts every booking status and shows what % of all rides
-- fall into each bucket (Success, Cancelled by Driver, Cancelled by
-- Customer, Driver Not Found).

SELECT
    booking_status,
    COUNT(*) AS total_rides,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM ola_rides_data), 2) AS pct_of_all_rides
FROM ola_rides_data
GROUP BY booking_status
ORDER BY total_rides DESC;

-- FINDING:
-- Only 62% of all rides booked actually complete successfully.
-- 38% of demand is lost: 17.91% cancelled by drivers, 10.20% cancelled
-- by customers, and 9.90% show "Driver Not Found" (no driver even
-- accepted the ride). Driver-side issues (cancel + not found = ~27.8%)
-- hurt the business almost 3x more than customer-side cancellations alone.

-- QUERY 2: CUSTOMER-SIDE CANCELLATION ROOT CAUSES (ranked)
-- Objective):
-- Out of all rides cancelled BY THE CUSTOMER, find out exactly which reason
-- customers pick the most, ranked from biggest to smallest, with a % share
-- so we know which problem to fix first.

SELECT
    canceled_rides_by_customer AS cancellation_reason,
    COUNT(*) AS total_cancellations,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*) FROM ola_rides_data WHERE canceled_rides_by_customer IS NOT NULL), 2) AS pct_share,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS reason_rank
FROM ola_rides_data
WHERE canceled_rides_by_customer IS NOT NULL
GROUP BY canceled_rides_by_customer
ORDER BY total_cancellations DESC;

-- FINDING:
-- "Driver is not moving towards pickup location" is the #1 reason customers
-- cancel (29.31% of all customer cancellations), closely followed by
-- "Driver asked to cancel" (26.53%). Together these two driver-linked
-- reasons cause 55.84% of ALL customer cancellations -- meaning more than
-- half of customer cancellations are actually caused by driver behavior,
-- not the customer's own choice. "Change of plans" (19.61%), "AC is Not
-- working" (15.38%) and "Wrong Address" (9.18%) follow.

-- QUERY 3: DRIVER-SIDE CANCELLATION ROOT CAUSES (ranked)
-- Objective:
-- Same idea as Query 2, but from the driver's side -- find out exactly why
-- drivers cancel rides, ranked by how often each reason occurs.

SELECT
    canceled_rides_by_driver AS cancellation_reason,
    COUNT(*) AS total_cancellations,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*) FROM ola_rides_data WHERE canceled_rides_by_driver IS NOT NULL), 2) AS pct_share,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS reason_rank
FROM ola_rides_data
WHERE canceled_rides_by_driver IS NOT NULL
GROUP BY canceled_rides_by_driver
ORDER BY total_cancellations DESC;

-- FINDING:
-- "Personal & Car related issue" is the top driver cancellation reason
-- (34.56%), followed by "Customer related issue" (29.12%),
-- "Customer was coughing/sick" (20.31%), and "More than permitted people
-- in there" (16.01%). Note that 3 out of these 4 reasons (65.44%) are
-- actually about the CUSTOMER (behaviour/health/headcount), not the
-- driver -- so driver-side cancellations are largely a customer-conduct
-- problem, while only the car-condition issue is truly the driver's fault.

-- QUERY 4: VEHICLE-TYPE WISE CANCELLATION RATE (ranked, using window function)
-- Objective:
-- Not all cars/bikes cancel equally. This finds, for every vehicle type,
-- what % of its total bookings end up cancelled (by either side), and
-- ranks vehicle types from worst to best so we know where to focus.

SELECT
    vehicle_type,
    COUNT(*)  AS total_bookings,
    SUM(CASE WHEN booking_status IN ('Canceled by Customer','Canceled by Driver')
             THEN 1 ELSE 0 END) AS total_cancellations,
    ROUND(100.0 * SUM(CASE WHEN booking_status IN ('Canceled by Customer','Canceled by Driver')
             THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_rate_pct,
    RANK() OVER (ORDER BY 100.0 * SUM(CASE WHEN booking_status IN
             ('Canceled by Customer','Canceled by Driver') THEN 1 ELSE 0 END) / COUNT(*) DESC) AS worst_rank
FROM ola_rides_data
GROUP BY vehicle_type
ORDER BY cancellation_rate_pct DESC;

-- FINDING:
-- Prime Plus has the highest cancellation rate at 30.31%, followed by
-- eBike (29.16%) and Prime SUV (28.05%). Bike (26.72%) and Prime Sedan
-- (26.93%) are the most reliable vehicle categories. The gap between
-- best and worst is about 3.6 percentage points -- small but meaningful
-- at OLA's scale, and it confirms premium vehicles (Prime Plus, Prime
-- SUV) genuinely cancel more often, supporting the "premium availability
-- issue" insight from the dashboard.

-- QUERY 5: REVENUE AT RISK FROM CANCELLATIONS (business impact in ₹)
-- Objective:
-- Cancellations aren't just an operational annoyance -- they cost real
-- money. This adds up the booking value of every ride that did NOT
-- complete successfully, and compares it to total potential revenue, to
-- show how much money is currently being lost/at risk.

SELECT
    SUM(CASE WHEN booking_status <> 'Success' THEN booking_value ELSE 0 END) AS revenue_at_risk,
    SUM(booking_value) AS total_potential_revenue,
    ROUND(100.0 * SUM(CASE WHEN booking_status <> 'Success' THEN booking_value ELSE 0 END)
        / SUM(booking_value), 2) AS pct_revenue_at_risk
FROM ola_rides_data;

-- FINDING:
-- Out of a total potential revenue of ₹1,11,48,671 across all booked
-- rides, ₹42,48,437 (38.11%) is tied up in rides that never completed.
-- This is not "lost" money in the strictest sense (cancelled rides were
-- never charged), but it represents the full-scale demand OLA is failing
-- to convert -- more than 1 out of every 3 rupees of ride demand is
-- currently walking away uncompleted.

-- QUERY 6: HOUR-OF-DAY CANCELLATION PATTERN
-- Objective:
-- Find out if cancellations spike at certain hours of the day (e.g. rush
-- hour, late night) so operations/support staffing can be planned around
-- the worst hours.

SELECT
    HOUR(time) AS hour_of_day,
    COUNT(*) AS total_cancellations
FROM ola_rides_data
WHERE booking_status IN ('Canceled by Customer','Canceled by Driver')
GROUP BY hour_of_day
ORDER BY total_cancellations DESC
LIMIT 10;

-- FINDING:
-- Cancellations are spread almost evenly across all 24 hours (roughly
-- 240-280 cancellations per hour, out of 5,735 total cancellations), with
-- only a mild peak around 10 AM, 4 AM and 8 PM. There is NO single
-- extreme rush-hour spike. This tells us the cancellation problem is
-- systemic (driver behaviour, car condition, app issues) rather than a
-- time-of-day demand-supply mismatch -- so the fix needs to be a policy
-- change, not just adding more drivers at a specific hour.

-- QUERY 7: DAY-OF-WEEK CANCELLATION PATTERN
-- Objective:
-- Check whether cancellations are worse on specific days of the week
-- (e.g. Monday blues, weekend rush) to guide day-wise driver incentive
-- planning.

SELECT
    DAYNAME(date) AS day_of_week,
    COUNT(*) AS total_cancellations,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*) FROM ola_rides_data
         WHERE booking_status IN ('Canceled by Customer','Canceled by Driver')), 2) AS pct_of_cancellations
FROM ola_rides_data
WHERE booking_status IN ('Canceled by Customer','Canceled by Driver')
GROUP BY day_of_week
ORDER BY total_cancellations DESC;

-- FINDING:
-- Tuesday (1,003 cancellations, 17.49%) and Monday (971, 16.93%) are the
-- worst days for cancellations -- together they account for 34.42% of
-- the week's cancellations even though they're only 2 of 7 days.
-- Saturday is the calmest day (720, 12.55%). This early-week spike could
-- be linked to driver fatigue/absenteeism after the weekend or higher
-- weekday commute pressure, and is a good candidate for a Monday-Tuesday
-- driver retention incentive.

-- QUERY 8: TOP 5 PICKUP-LOCATION HOTSPOTS FOR CUSTOMER CANCELLATIONS
-- Objective:
-- Find the specific pickup areas where customers cancel the most. If a
-- few locations dominate, that points to a local supply/road/traffic
-- problem rather than a company-wide issue.

SELECT
    pickup_location,
    COUNT(*)  AS customer_cancellations,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS hotspot_rank
FROM ola_rides_data
WHERE booking_status = 'Canceled by Customer'
GROUP BY pickup_location
ORDER BY customer_cancellations DESC
LIMIT 5;

-- FINDING:
-- Kammanahalli (54), Mysore Road (52), Sahakar Nagar (51), Peenya (51)
-- and Vijayanagar (50) are the top 5 pickup hotspots for customer
-- cancellations. With 50 pickup locations sharing 2,081 customer
-- cancellations, an average location sees about 42 cancellations --
-- these 5 hotspots run about 20-30% above that average, a consistent
-- enough gap to justify a targeted local review (driver supply, road/
-- traffic conditions, address-accuracy issues) in these specific zones.

-- QUERY 9: VEHICLE-TYPE BREAKDOWN OF "PERSONAL & CAR RELATED ISSUE"
--          (the #1 driver-side cancellation reason from Query 3)
-- Objective:
-- We know "Personal & Car related issue" is the top reason drivers cancel.
-- Now drill one level deeper: WHICH vehicle types suffer most from this
-- specific reason? This tells us exactly which fleet segment needs
-- vehicle-maintenance support.

SELECT
    vehicle_type,
    COUNT(*)  AS car_issue_cancellations,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*) FROM ola_rides_data
         WHERE canceled_rides_by_driver = 'Personal & Car related issue'), 2) AS pct_share
FROM ola_rides_data
WHERE canceled_rides_by_driver = 'Personal & Car related issue'
GROUP BY vehicle_type
ORDER BY car_issue_cancellations DESC;

-- FINDING:
-- Prime SUV (201 cases, 15.91%) and Prime Plus (191 cases, 15.12%) --
-- OLA's premium vehicle categories -- have the highest number of
-- "Personal & Car related issue" cancellations, ahead of Auto (187),
-- eBike (180), Bike (172), Prime Sedan (169) and Mini (163). This
-- directly supports the recommendation to prioritize vehicle maintenance
-- and driver training for the premium fleet first, since these vehicles
-- are supposed to be OLA's flagship, high-fare experience.

-- QUERY 10: "DRIVER NOT FOUND" ANALYSIS BY VEHICLE TYPE (supply-gap check)
-- Objective:
-- "Driver Not Found" is a hidden cancellation root-cause: the ride never
-- even got a driver assigned. This shows which vehicle types face the
-- worst driver-availability / supply shortage.

SELECT
    vehicle_type,
    COUNT(*) AS driver_not_found_cnt,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*) FROM ola_rides_data WHERE booking_status = 'Driver Not Found'), 2) AS pct_share
FROM ola_rides_data
WHERE booking_status = 'Driver Not Found'
GROUP BY vehicle_type
ORDER BY driver_not_found_cnt DESC;

-- FINDING:
-- Prime SUV again tops the list with 335 "Driver Not Found" cases
-- (16.58% of all such cases), followed by Bike (307, 15.20%), Prime
-- Sedan (300, 14.85%) and Auto (296, 14.65%). eBike has the fewest
-- (255, 12.62%). Combined with Query 9, Prime SUV shows up as the
-- single most supply-constrained vehicle type in the fleet -- both in
-- terms of drivers cancelling AND drivers simply not being available --
-- making it the #1 priority category for fleet expansion.

