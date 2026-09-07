/* =========================================================
   MUSIC STORE SQL ANALYSIS
   Database: Chinook (digital music store)
   Author: Bhavya Bansal
   =========================================================
   Each section below answers one business question with a
   commented SQL query. Run against chinook.db (SQLite).
   ========================================================= */


/* -----------------------------------------------------------
   Q1. Who are our top 10 customers by total amount spent?
   Why it matters: identifies high-value customers worth
   targeting for loyalty programs or personalized offers.
----------------------------------------------------------- */
SELECT
    c.CustomerId,
    c.FirstName || ' ' || c.LastName AS CustomerName,
    c.Country,
    ROUND(SUM(i.Total), 2) AS TotalSpent
FROM Customer c
JOIN Invoice i ON c.CustomerId = i.CustomerId
GROUP BY c.CustomerId, CustomerName, c.Country
ORDER BY TotalSpent DESC
LIMIT 10;


/* -----------------------------------------------------------
   Q2. Which countries generate the most revenue, and what
   share of total revenue does each represent?
   Why it matters: helps prioritize which markets to focus
   marketing/inventory spend on.
----------------------------------------------------------- */
SELECT
    BillingCountry,
    ROUND(SUM(Total), 2) AS Revenue,
    ROUND(100.0 * SUM(Total) / (SELECT SUM(Total) FROM Invoice), 2) AS PctOfTotalRevenue
FROM Invoice
GROUP BY BillingCountry
ORDER BY Revenue DESC;


/* -----------------------------------------------------------
   Q3. What are the top 5 best-selling genres by number of
   tracks sold?
   Why it matters: informs which genres to expand inventory
   in.
----------------------------------------------------------- */
SELECT
    g.Name AS Genre,
    COUNT(il.InvoiceLineId) AS TracksSold,
    ROUND(SUM(il.UnitPrice * il.Quantity), 2) AS Revenue
FROM InvoiceLine il
JOIN Track t ON il.TrackId = t.TrackId
JOIN Genre g ON t.GenreId = g.GenreId
GROUP BY g.Name
ORDER BY TracksSold DESC
LIMIT 5;


/* -----------------------------------------------------------
   Q4. Which sales employee (support rep) has generated the
   most revenue, and how does each rep compare?
   Why it matters: performance review / commission input.
----------------------------------------------------------- */
SELECT
    e.EmployeeId,
    e.FirstName || ' ' || e.LastName AS EmployeeName,
    e.Title,
    ROUND(SUM(i.Total), 2) AS RevenueGenerated,
    COUNT(DISTINCT c.CustomerId) AS CustomersHandled
FROM Employee e
JOIN Customer c ON c.SupportRepId = e.EmployeeId
JOIN Invoice i ON i.CustomerId = c.CustomerId
GROUP BY e.EmployeeId, EmployeeName, e.Title
ORDER BY RevenueGenerated DESC;


/* -----------------------------------------------------------
   Q5. What is the month-over-month revenue trend across the
   full dataset?
   Why it matters: spotting seasonality or growth/decline.
----------------------------------------------------------- */
SELECT
    strftime('%Y-%m', InvoiceDate) AS Month,
    ROUND(SUM(Total), 2) AS Revenue
FROM Invoice
GROUP BY Month
ORDER BY Month;


/* -----------------------------------------------------------
   Q6. Rank customers within each country by total spend
   (using a window function) — who is the top spender in
   every country?
   Why it matters: shows window-function proficiency and
   surfaces regional VIP customers.
----------------------------------------------------------- */
WITH CustomerSpend AS (
    SELECT
        c.CustomerId,
        c.FirstName || ' ' || c.LastName AS CustomerName,
        c.Country,
        SUM(i.Total) AS TotalSpent
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId, CustomerName, c.Country
)
SELECT
    Country,
    CustomerName,
    ROUND(TotalSpent, 2) AS TotalSpent,
    RANK() OVER (PARTITION BY Country ORDER BY TotalSpent DESC) AS RankInCountry
FROM CustomerSpend
QUALIFY RankInCountry = 1
ORDER BY TotalSpent DESC;
-- Note: SQLite doesn't support QUALIFY natively pre-3.42 in all builds;
-- if it errors, wrap in a subquery and filter with WHERE instead (see Q6b).


/* -----------------------------------------------------------
   Q6b. Same as Q6, portable version using a subquery instead
   of QUALIFY (works on any SQLite version).
----------------------------------------------------------- */
SELECT * FROM (
    SELECT
        c.Country,
        c.FirstName || ' ' || c.LastName AS CustomerName,
        ROUND(SUM(i.Total), 2) AS TotalSpent,
        RANK() OVER (PARTITION BY c.Country ORDER BY SUM(i.Total) DESC) AS RankInCountry
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.Country, CustomerName
) ranked
WHERE RankInCountry = 1
ORDER BY TotalSpent DESC;


/* -----------------------------------------------------------
   Q7. What is the average order value (AOV) per country, and
   how many orders does each country have?
   Why it matters: distinguishes "many small orders" markets
   from "few big orders" markets — different strategies apply.
----------------------------------------------------------- */
SELECT
    BillingCountry,
    COUNT(InvoiceId) AS NumOrders,
    ROUND(AVG(Total), 2) AS AvgOrderValue
FROM Invoice
GROUP BY BillingCountry
HAVING COUNT(InvoiceId) >= 5
ORDER BY AvgOrderValue DESC;


/* -----------------------------------------------------------
   Q8. Which artists have generated the most total revenue?
   Why it matters: identifies which catalog/licensing
   relationships are most valuable to the business.
----------------------------------------------------------- */
SELECT
    ar.Name AS Artist,
    ROUND(SUM(il.UnitPrice * il.Quantity), 2) AS Revenue,
    COUNT(il.InvoiceLineId) AS TracksSold
FROM InvoiceLine il
JOIN Track t ON il.TrackId = t.TrackId
JOIN Album al ON t.AlbumId = al.AlbumId
JOIN Artist ar ON al.ArtistId = ar.ArtistId
GROUP BY ar.Name
ORDER BY Revenue DESC
LIMIT 10;


/* -----------------------------------------------------------
   Q9. What percentage of tracks in the catalog have never
   been purchased (dead inventory)?
   Why it matters: flags catalog that could be delisted or
   needs promotion.
----------------------------------------------------------- */
SELECT
    (SELECT COUNT(*) FROM Track) AS TotalTracks,
    (SELECT COUNT(DISTINCT TrackId) FROM InvoiceLine) AS TracksSoldAtLeastOnce,
    ROUND(
        100.0 * (
            (SELECT COUNT(*) FROM Track) - (SELECT COUNT(DISTINCT TrackId) FROM InvoiceLine)
        ) / (SELECT COUNT(*) FROM Track), 2
    ) AS PctNeverSold;


/* -----------------------------------------------------------
   Q10. Using a running total, how does cumulative revenue
   build up month by month across the dataset's lifetime?
   Why it matters: demonstrates LAG/window-function-style
   cumulative analysis, useful for growth storytelling.
----------------------------------------------------------- */
SELECT
    Month,
    Revenue,
    ROUND(SUM(Revenue) OVER (ORDER BY Month), 2) AS CumulativeRevenue
FROM (
    SELECT
        strftime('%Y-%m', InvoiceDate) AS Month,
        SUM(Total) AS Revenue
    FROM Invoice
    GROUP BY Month
)
ORDER BY Month;


/* -----------------------------------------------------------
   Q11. Which customers have not made a purchase in the most
   recent 6 months of data available (churn risk)?
   Why it matters: gives the business a re-engagement target
   list.
----------------------------------------------------------- */
WITH LastPurchase AS (
    SELECT
        c.CustomerId,
        c.FirstName || ' ' || c.LastName AS CustomerName,
        MAX(i.InvoiceDate) AS LastOrderDate
    FROM Customer c
    JOIN Invoice i ON c.CustomerId = i.CustomerId
    GROUP BY c.CustomerId, CustomerName
),
MaxDate AS (
    SELECT MAX(InvoiceDate) AS DatasetMaxDate FROM Invoice
)
SELECT
    lp.CustomerName,
    lp.LastOrderDate
FROM LastPurchase lp, MaxDate md
WHERE julianday(md.DatasetMaxDate) - julianday(lp.LastOrderDate) > 180
ORDER BY lp.LastOrderDate ASC;


/* -----------------------------------------------------------
   Q12. What is the average track length by genre, and which
   genres skew toward longer-format listening?
   Why it matters: informs playlist curation / bundling
   strategy (e.g. long-form genres for background listening).
----------------------------------------------------------- */
SELECT
    g.Name AS Genre,
    COUNT(t.TrackId) AS NumTracks,
    ROUND(AVG(t.Milliseconds) / 60000.0, 2) AS AvgLengthMinutes
FROM Track t
JOIN Genre g ON t.GenreId = g.GenreId
GROUP BY g.Name
ORDER BY AvgLengthMinutes DESC;
