USE [master]
GO
/****** Object:  Database [KPIs]    Script Date: 9/22/2016 2:43:45 PM ******/
CREATE DATABASE [KPIs]
 CONTAINMENT = NONE
 ON  PRIMARY 
( NAME = N'KPIs', FILENAME = N'E:\MSSQL\DATA\KPIs.mdf' , SIZE = 103424KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB )
 LOG ON 
( NAME = N'KPIs_log', FILENAME = N'E:\MSSQL\DATA\KPIs_log.ldf' , SIZE = 291648KB , MAXSIZE = 2048GB , FILEGROWTH = 10%)
GO
ALTER DATABASE [KPIs] SET COMPATIBILITY_LEVEL = 100
GO
IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
begin
EXEC [KPIs].[dbo].[sp_fulltext_database] @action = 'enable'
end
GO
ALTER DATABASE [KPIs] SET ANSI_NULL_DEFAULT OFF 
GO
ALTER DATABASE [KPIs] SET ANSI_NULLS OFF 
GO
ALTER DATABASE [KPIs] SET ANSI_PADDING OFF 
GO
ALTER DATABASE [KPIs] SET ANSI_WARNINGS OFF 
GO
ALTER DATABASE [KPIs] SET ARITHABORT OFF 
GO
ALTER DATABASE [KPIs] SET AUTO_CLOSE OFF 
GO
ALTER DATABASE [KPIs] SET AUTO_CREATE_STATISTICS ON 
GO
ALTER DATABASE [KPIs] SET AUTO_SHRINK OFF 
GO
ALTER DATABASE [KPIs] SET AUTO_UPDATE_STATISTICS ON 
GO
ALTER DATABASE [KPIs] SET CURSOR_CLOSE_ON_COMMIT OFF 
GO
ALTER DATABASE [KPIs] SET CURSOR_DEFAULT  GLOBAL 
GO
ALTER DATABASE [KPIs] SET CONCAT_NULL_YIELDS_NULL OFF 
GO
ALTER DATABASE [KPIs] SET NUMERIC_ROUNDABORT OFF 
GO
ALTER DATABASE [KPIs] SET QUOTED_IDENTIFIER OFF 
GO
ALTER DATABASE [KPIs] SET RECURSIVE_TRIGGERS OFF 
GO
ALTER DATABASE [KPIs] SET  DISABLE_BROKER 
GO
ALTER DATABASE [KPIs] SET AUTO_UPDATE_STATISTICS_ASYNC OFF 
GO
ALTER DATABASE [KPIs] SET DATE_CORRELATION_OPTIMIZATION OFF 
GO
ALTER DATABASE [KPIs] SET TRUSTWORTHY OFF 
GO
ALTER DATABASE [KPIs] SET ALLOW_SNAPSHOT_ISOLATION OFF 
GO
ALTER DATABASE [KPIs] SET PARAMETERIZATION SIMPLE 
GO
ALTER DATABASE [KPIs] SET READ_COMMITTED_SNAPSHOT OFF 
GO
ALTER DATABASE [KPIs] SET HONOR_BROKER_PRIORITY OFF 
GO
ALTER DATABASE [KPIs] SET RECOVERY SIMPLE 
GO
ALTER DATABASE [KPIs] SET  MULTI_USER 
GO
ALTER DATABASE [KPIs] SET PAGE_VERIFY CHECKSUM  
GO
ALTER DATABASE [KPIs] SET DB_CHAINING OFF 
GO
ALTER DATABASE [KPIs] SET FILESTREAM( NON_TRANSACTED_ACCESS = OFF ) 
GO
ALTER DATABASE [KPIs] SET TARGET_RECOVERY_TIME = 0 SECONDS 
GO
USE [KPIs]
GO
/****** Object:  User [wwAdmin]    Script Date: 9/22/2016 2:43:45 PM ******/
CREATE USER [wwAdmin] WITHOUT LOGIN WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [wwAdmin]
GO
/****** Object:  StoredProcedure [dbo].[kpiCalculateDashboard]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[kpiCalculateDashboard] AS

SET NOCOUNT ON

---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

---CURRENT HOUR AVAILABILITY---

DECLARE @MaxPeriodID int

SELECT @MaxPeriodID = MAX(kpi.PeriodID) 
FROM [KPIs].[dbo].[kpiData] kpi

SELECT * INTO #TEMP 
FROM (
	SELECT MAX(eqp.System) System, SUM(data.TotalAvailMins) TotalAvailMins, SUM(data.TotalRunMins) TotalRunMins 
	FROM [KPIs].[dbo].[kpiEquipment] eqp

	LEFT JOIN (
		SELECT MAX(kpi.EquipTag) EquipTag, MAX(kpi.PeriodID) PeriodID, SUM(kpi.RunMins) TotalRunMins, SUM(kpi.AvailMins) TotalAvailMins
		FROM [KPIs].[dbo].[kpiData] kpi
		WHERE PeriodID = @MaxPeriodID
		GROUP BY EquipTag) AS data

	ON eqp.EquipTag = data.EquipTag

	GROUP BY eqp.System) AS x

---Update kpiDashBoardSummary
MERGE INTO [KPIs].[dbo].kpiDashBoardSummary dsh
USING #TEMP temp
ON temp.System = dsh.System
	AND dsh.SummaryLevel = 1
WHEN MATCHED THEN
UPDATE
	SET dsh.Availability = ROUND(((temp.TotalRunMins / temp.TotalAvailMins) * 100), 2);

DROP TABLE #TEMP

---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

---CURRENT SHIFT AVAILABILITY---

SELECT * INTO #TEMP2 
FROM (

	SELECT MAX(eqp.System) System, SUM(data.TotalAvailMins) TotalAvailMins, SUM(data.TotalRunMins) TotalRunMins 
	FROM [KPIs].[dbo].[kpiEquipment] eqp

	LEFT JOIN (
		SELECT MAX(kpi.EquipTag) EquipTag, SUM(kpi.RunMins) TotalRunMins, SUM(kpi.AvailMins) TotalAvailMins
		FROM [KPIs].[dbo].[kpiData] kpi
		WHERE PeriodID IN (
			SELECT allperiods.PeriodID FROM (
				SELECT PeriodShift
				FROM [KPIs].[dbo].[kpiPeriods]
				WHERE getdate() BETWEEN PeriodStart AND PeriodEnd) curperiod

				LEFT JOIN (
					SELECT PeriodID, PeriodShift
					FROM [KPIs].[dbo].[kpiPeriods]
					WHERE PeriodStart BETWEEN dateadd(day,-1,dateadd(hour,19,(convert(datetime, convert(date, getdate()))))) AND GETDATE()) allperiods
			
				ON curperiod.PeriodShift = allperiods.PeriodShift)
				GROUP BY EquipTag) AS data

	ON eqp.EquipTag = data.EquipTag

	GROUP BY eqp.System) AS x

---Update kpiDashBoardSummary
MERGE INTO [KPIs].[dbo].kpiDashBoardSummary dsh
USING #TEMP2 TEMP2
	ON TEMP2.System = dsh.System
		AND dsh.SummaryLevel = 2
WHEN MATCHED THEN
UPDATE
	SET dsh.Availability = ROUND(((TEMP2.TotalRunMins / TEMP2.TotalAvailMins ) * 100), 2);

DROP TABLE #TEMP2

---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

---CURRENT DAY AVAILABILITY---

SELECT * INTO #TEMP3 
FROM (

	SELECT MAX(eqp.System) System, SUM(data.TotalAvailMins) TotalAvailMins, SUM(data.TotalRunMins) TotalRunMins 
	FROM [KPIs].[dbo].[kpiEquipment] eqp

	LEFT JOIN (
		SELECT MAX(kpi.EquipTag) EquipTag, SUM(kpi.RunMins) TotalRunMins, SUM(kpi.AvailMins) TotalAvailMins
		FROM [KPIs].[dbo].[kpiData] kpi
		WHERE PeriodID IN (
			SELECT PeriodID
			FROM [KPIs].[dbo].[kpiPeriods]
			WHERE PeriodStart BETWEEN dateadd(day,-1,dateadd(hour,19,(convert(datetime, convert(date, getdate()))))) AND GETDATE())
			GROUP BY EquipTag) AS data

	ON eqp.EquipTag = data.EquipTag

	GROUP BY eqp.System) AS x

---Update kpiDashBoardSummary
MERGE INTO [KPIs].[dbo].kpiDashBoardSummary dsh
USING #TEMP3 TEMP3
	ON TEMP3.System = dsh.System
		AND dsh.SummaryLevel = 3
WHEN MATCHED THEN
UPDATE
	SET dsh.Availability = ROUND(((TEMP3.TotalRunMins / TEMP3.TotalAvailMins) * 100), 2);

DROP TABLE #TEMP3

---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
---CURRENT HOUR OEE---
SELECT * INTO #TEMP10 FROM (

	SELECT
		(((x.AVGOutletGPM * x.AvgLbPerGal) * y.YieldAdjust) / (y.ProductionRate * 694.44)) OEE,
		
		x.System,
		x.AVGOutletGPM,
		x.AvgLbPerGal,
		x.AvailMins,
		x.OrderID,
		y.YieldAdjust,
		y.ProductionRate
		FROM

	(SELECT 
		MAX(eqp.System) System, 
		SUM(data.AVGOutletGPM) AVGOutletGPM, 
		AVG(data.AvgLbPerGal) AvgLbPerGal,
		SUM(data.AvailMins) AvailMins, 
		MAX(data.OrderID) OrderID
	FROM [KPIs].[dbo].[kpiEquipment] eqp

	LEFT JOIN (
		SELECT 
		MAX(kpi.EquipTag) EquipTag, 
		MAX(kpi.PeriodID) PeriodID, 
		--AVG(kpi.AvgOutletGPM) AVGOutletGPM,
		AVGOutletGPM =
			CASE WHEN kpi.EquipTag LIKE 'T%' THEN AVG(kpi.AvgOutletGPM)
				WHEN kpi.EquipTag LIKE 'D%' THEN AVG(kpi.AvgInletGPM)
			END,
		--AVG(kpi.AvgLbPerGal) AVGlbPerGal,
		AVGlbPerGal =
			CASE WHEN kpi.EquipTag LIKE 'T%' THEN AVG(kpi.AvgLbPerGal)
				WHEN kpi.EquipTag LIKE 'D%' THEN 8.5
			END, 
		MAX(kpi.OrderID) OrderID, 
		SUM(kpi.AvailMins) AvailMins
		FROM [KPIs].[dbo].[kpiData] kpi
		WHERE PeriodID = @MaxPeriodID
		GROUP BY EquipTag, OrderID) AS data

	ON eqp.EquipTag = data.EquipTag
	--WHERE eqp.System LIKE 'P%'
	GROUP BY eqp.System, data.OrderID) as x

	LEFT JOIN
	[KPIs].[dbo].[kpiOrders] y
	ON x.OrderID = y.OrderID) AS A

SELECT * INTO #TEMP11 FROM(

SELECT
	tmp.System,
	tmp.OrderID,
	(tmp.OEE * tmp.AvailMins / x.SystemAvailMins) AS ProportionOEE

FROM #TEMP10 tmp

LEFT JOIN (

---FIND TOTAL AVAILABLE MINUTES PER SYSTEM
SELECT 
		MAX(eqp.System) System,
		SUM(data.AvailMins) SystemAvailMins, 
		MAX(data.OrderID) OrderID
	FROM [KPIs].[dbo].[kpiEquipment] eqp
	LEFT JOIN 
		(SELECT MAX(EquipTag) EquipTag, SUM(AvailMins) AvailMins, MAX(OrderID) OrderID FROM [KPIs].[dbo].[kpiData] kpi
			WHERE PeriodID = @MaxPeriodID
			GROUP BY EquipTag, OrderID) AS data
	ON data.EquipTag = eqp.EquipTag
	GROUP BY System) AS x
	ON tmp.System = x.System) AS a

SELECT * INTO #TEMP12 FROM (SELECT
	MAX(System) System, 
	ROUND(SUM(ProportionOEE), 4) * 100 OEE 
	FROM #TEMP11 
	GROUP BY System) AS b


MERGE INTO [KPIs].[dbo].kpiDashBoardSummary dsh
USING #TEMP12 temp
ON temp.System = dsh.System
	AND dsh.SummaryLevel = 1
WHEN MATCHED THEN
UPDATE
	SET dsh.OEE = temp.OEE;

DROP TABLE #TEMP10
DROP TABLE #TEMP11
DROP TABLE #TEMP12

---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
---CURRENT SHIFT OEE---
SELECT * INTO #TEMP13 FROM (

	SELECT
		---694.44 comes from ((production rate * 1,000,000) / 1440 minutes per day) times 100 to get a percentage
		(((x.AVGOutletGPM * x.AvgLbPerGal) * y.YieldAdjust) / (y.ProductionRate * 694.44)) OEE,
		
		x.System,
		x.AVGOutletGPM,
		x.AvgLbPerGal,
		x.AvailMins,
		x.OrderID,
		y.YieldAdjust,
		y.ProductionRate
		FROM

	(SELECT 
		MAX(eqp.System) System, 
		SUM(data.AVGOutletGPM) AVGOutletGPM, 
		AVG(data.AvgLbPerGal) AvgLbPerGal,
		SUM(data.AvailMins) AvailMins, 
		MAX(data.OrderID) OrderID
	FROM [KPIs].[dbo].[kpiEquipment] eqp

	LEFT JOIN (
		SELECT 
		MAX(kpi.EquipTag) EquipTag, 
		MAX(kpi.PeriodID) PeriodID, 
		--AVG(kpi.AvgOutletGPM) AVGOutletGPM,
		AVGOutletGPM = 
			CASE WHEN kpi.EquipTag LIKE 'T%' THEN AVG(kpi.AvgOutletGPM)
				WHEN kpi.EquipTag LIKE 'D%' THEN AVG(kpi.AvgInletGPM)
			END,
		--AVG(kpi.AvgLbPerGal) AVGlbPerGal,
		AVGlbPerGal =
			CASE WHEN kpi.EquipTag LIKE 'T%' THEN AVG(kpi.AvgLbPerGal)
				WHEN kpi.EquipTag LIKE 'D%' THEN 8.5
			END,  
		MAX(kpi.OrderID) OrderID, 
		SUM(kpi.AvailMins) AvailMins
		FROM [KPIs].[dbo].[kpiData] kpi
		WHERE PeriodID IN (SELECT allperiods.PeriodID FROM (
		SELECT PeriodShift
		FROM [KPIs].[dbo].[kpiPeriods]
		WHERE getdate() BETWEEN PeriodStart AND PeriodEnd) curperiod

		LEFT JOIN (
			SELECT PeriodID, PeriodShift
			FROM [KPIs].[dbo].[kpiPeriods]
			WHERE PeriodStart BETWEEN dateadd(day,-1,dateadd(hour,19,(convert(datetime, convert(date, getdate()))))) AND GETDATE()) allperiods

		ON curperiod.PeriodShift = allperiods.PeriodShift)
		GROUP BY EquipTag, OrderID) AS data

	ON eqp.EquipTag = data.EquipTag
	--WHERE eqp.System LIKE 'P%'
	GROUP BY eqp.System, data.OrderID) as x

	LEFT JOIN
	[KPIs].[dbo].[kpiOrders] y
	ON x.OrderID = y.OrderID) AS A
	

SELECT * INTO #TEMP14 FROM(

SELECT
	tmp.System,
	tmp.OrderID,
	(tmp.OEE * tmp.AvailMins / x.SystemAvailMins) AS ProportionOEE

FROM #TEMP13 tmp

LEFT JOIN (

---FIND TOTAL AVAILABLE MINUTES PER SYSTEM
SELECT 
		MAX(eqp.System) System,
		SUM(data.AvailMins) SystemAvailMins, 
		MAX(data.OrderID) OrderID
	FROM [KPIs].[dbo].[kpiEquipment] eqp
	LEFT JOIN 
		(SELECT MAX(EquipTag) EquipTag, SUM(AvailMins) AvailMins, MAX(OrderID) OrderID FROM [KPIs].[dbo].[kpiData] kpi
			WHERE PeriodID IN (SELECT allperiods.PeriodID FROM (
		SELECT PeriodShift
		FROM [KPIs].[dbo].[kpiPeriods]
		WHERE getdate() BETWEEN PeriodStart AND PeriodEnd) curperiod

		LEFT JOIN (
			SELECT PeriodID, PeriodShift
			FROM [KPIs].[dbo].[kpiPeriods]
			WHERE PeriodStart BETWEEN dateadd(day,-1,dateadd(hour,19,(convert(datetime, convert(date, getdate()))))) AND GETDATE()) allperiods

		ON curperiod.PeriodShift = allperiods.PeriodShift)
			GROUP BY EquipTag, OrderID) AS data
	ON data.EquipTag = eqp.EquipTag
	GROUP BY System) AS x
	ON tmp.System = x.System) AS a

SELECT * INTO #TEMP15 FROM (SELECT
	MAX(System) System, 
	ROUND(SUM(ProportionOEE), 4) * 100 OEE 
	FROM #TEMP14 
	GROUP BY System) AS b


MERGE INTO [KPIs].[dbo].kpiDashBoardSummary dsh
USING #TEMP15 temp
ON temp.System = dsh.System
	AND dsh.SummaryLevel = 2
WHEN MATCHED THEN
UPDATE
	SET dsh.OEE = temp.OEE;

DROP TABLE #TEMP13
DROP TABLE #TEMP14
DROP TABLE #TEMP15


---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
---CURRENT DAY OEE---
SELECT * INTO #TEMP16 FROM (

	SELECT
		(((x.AVGOutletGPM * x.AvgLbPerGal) * y.YieldAdjust) / (y.ProductionRate * 694.44)) OEE,
		
		x.System,
		x.AVGOutletGPM,
		x.AvgLbPerGal,
		x.AvailMins,
		x.OrderID,
		y.YieldAdjust,
		y.ProductionRate
		FROM

	(SELECT 
		MAX(eqp.System) System, 
		SUM(data.AVGOutletGPM) AVGOutletGPM, 
		AVG(data.AvgLbPerGal) AvgLbPerGal,
		SUM(data.AvailMins) AvailMins, 
		MAX(data.OrderID) OrderID
	FROM [KPIs].[dbo].[kpiEquipment] eqp

	LEFT JOIN (
		SELECT MAX(kpi.EquipTag) EquipTag, 
		MAX(kpi.PeriodID) PeriodID, 
		---AVG(kpi.AvgOutletGPM) AVGOutletGPM, 
		AVGOutletGPM = 
			CASE WHEN kpi.EquipTag LIKE 'T%' THEN AVG(kpi.AvgOutletGPM)
				WHEN kpi.EquipTag LIKE 'D%' THEN AVG(kpi.AvgInletGPM)
			END,
		--AVG(kpi.AvgLbPerGal) AVGlbPerGal, 
		AVGlbPerGal =
			CASE WHEN kpi.EquipTag LIKE 'T%' THEN AVG(kpi.AvgLbPerGal)
				WHEN kpi.EquipTag LIKE 'D%' THEN 8.5
			END,
		MAX(kpi.OrderID) OrderID, 
		SUM(kpi.AvailMins) AvailMins
		FROM [KPIs].[dbo].[kpiData] kpi
		WHERE PeriodID IN (SELECT PeriodID
		FROM [KPIs].[dbo].[kpiPeriods]
		WHERE PeriodStart BETWEEN dateadd(day,-1,dateadd(hour,19,(convert(datetime, convert(date, getdate()))))) AND GETDATE())
		GROUP BY EquipTag, OrderID) AS data

	ON eqp.EquipTag = data.EquipTag
	--WHERE eqp.System LIKE 'P%'
	GROUP BY eqp.System, data.OrderID) as x

	LEFT JOIN
	[KPIs].[dbo].[kpiOrders] y
	ON x.OrderID = y.OrderID) AS A
	

SELECT * INTO #TEMP17 FROM(

SELECT
	tmp.System,
	tmp.OrderID,
	(tmp.OEE * tmp.AvailMins / x.SystemAvailMins) AS ProportionOEE

FROM #TEMP16 tmp

LEFT JOIN (

---FIND TOTAL AVAILABLE MINUTES PER SYSTEM
SELECT 
		MAX(eqp.System) System,
		SUM(data.AvailMins) SystemAvailMins, 
		MAX(data.OrderID) OrderID
	FROM [KPIs].[dbo].[kpiEquipment] eqp
	LEFT JOIN 
		(SELECT MAX(EquipTag) EquipTag, SUM(AvailMins) AvailMins, MAX(OrderID) OrderID FROM [KPIs].[dbo].[kpiData] kpi
			WHERE PeriodID IN (SELECT PeriodID
		FROM [KPIs].[dbo].[kpiPeriods]
		WHERE PeriodStart BETWEEN dateadd(day,-1,dateadd(hour,19,(convert(datetime, convert(date, getdate()))))) AND GETDATE())
			GROUP BY EquipTag, OrderID) AS data
	ON data.EquipTag = eqp.EquipTag
	GROUP BY System) AS x
	ON tmp.System = x.System) AS a

SELECT * INTO #TEMP18 FROM (SELECT
	MAX(System) System, 
	ROUND(SUM(ProportionOEE), 4) * 100 OEE 
	FROM #TEMP17 
	GROUP BY System) AS b


MERGE INTO [KPIs].[dbo].kpiDashBoardSummary dsh
USING #TEMP18 temp
ON temp.System = dsh.System
	AND dsh.SummaryLevel = 3
WHEN MATCHED THEN
UPDATE
	SET dsh.OEE = temp.OEE;

DROP TABLE #TEMP16
DROP TABLE #TEMP17
DROP TABLE #TEMP18
/*
UPDATE [KPIs].[dbo].[kpiData] SET OrderID = '10001' WHERE EquipTag LIKE 'D1%' AND PeriodID > '21146'
UPDATE [KPIs].[dbo].[kpiData] SET OrderID = '10002' WHERE EquipTag LIKE 'T24%' AND PeriodID > '21146'
UPDATE [KPIs].[dbo].[kpiData] SET OrderID = '10003' WHERE EquipTag LIKE 'T20%' AND PeriodID > '21146'
*/

---UPDATE OEE IN DASHBOARD---

UPDATE [KPIs].[dbo].kpiDashBoardSummary SET Performance = ROUND(((OEE / Availability) * 100), 2)
GO
/****** Object:  StoredProcedure [dbo].[kpiCalculateFromHistorian]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[kpiCalculateFromHistorian] AS

SET NOCOUNT ON

/* Global Variables */
DECLARE @CurPeriodRow int
DECLARE @MaxPeriodRows int

/* Variables for Periods Loop */
DECLARE @PeriodID int
DECLARE @PeriodStatus int
DECLARE @PeriodMinute int
DECLARE @StartDate DateTime
DECLARE @EndDate DateTime
DECLARE @ActiveOrderID int

/* Variables for Equipment Loop */
DECLARE @EquipTag varchar(64)
DECLARE @InletFlowTag varchar(64)
DECLARE @OutletFlowTag varchar(64)
DECLARE @BrixTag varchar(64)
DECLARE @MinFlow float

/* Set Execution Loop Limits */
SET @CurPeriodRow = 0
SET @MaxPeriodRows = 24

/* Period Status is Null for Open Hourly Periods But Reflects The Latest Minute Processed for Current Period */
DECLARE Periods_Cursor CURSOR LOCAL FAST_FORWARD FOR
	SELECT PeriodID, PeriodStart, PeriodEnd, ISNULL(PeriodStatus, 0)
		FROM dbo.kpiPeriods
		WHERE (PeriodStatus IS NULL AND PeriodStart < getdate())
			OR (PeriodStatus < 59)
		ORDER BY PeriodID		
OPEN Periods_Cursor

/* Equipment Cursor Moves through tag lists for each piece of equipment */
DECLARE Equip_Cursor CURSOR LOCAL SCROLL FOR
	SELECT EquipTag, InletFlowTag, ISNULL(OutletFlowTag, ''), ISNULL(BrixTag, ''), MinFlow, sy.ActiveOrderID
		FROM dbo.kpiEquipment eq
		INNER JOIN dbo.kpiSystems sy on eq.System = sy.System
OPEN Equip_Cursor

/*  SAVED FOR TESTING ONLY
SET @StartDate = '20160729 14:00:00.000'
SET @EndDate = '20160729 15:00:00.000'

SET @EquipTag = 'T200'
SET @InletFlowTag = 'T200_V426'
SET @OutletFlowTag = 'T200_V423'
SET @BrixTag = 'T200_Lp08_LPV'
SET @MinFlow = 50.0
*/

/* Begin Periods Cursor Loop */
FETCH NEXT FROM Periods_Cursor INTO @PeriodID, @StartDate, @EndDate, @PeriodStatus
WHILE (@@FETCH_STATUS = 0) AND (@CurPeriodRow < @MaxPeriodRows)
	BEGIN -- Periods Cursor Loop
	SET @CurPeriodRow = @CurPeriodRow + 1
	/* Determine if Processing A Current/Partial Period or Full Period */
	IF @EndDate >= getdate()
		BEGIN -- Current Hourly Period
		SET @PeriodMinute = DATEDIFF(mi, @StartDate, GETDATE())
		SET @PeriodMinute = CASE WHEN @PeriodMinute > 60 THEN 60 ELSE @PeriodMinute END
		SET @EndDate = DATEADD(mi, @PeriodMinute, @StartDate)
		SET @StartDate = DATEADD(mi, ISNULL(@PeriodStatus, 0), @StartDate)
		END -- Current Hourly Period 
	ELSE
		BEGIN -- Full/Historical Hourly Period
		SET @PeriodMinute = 60
		END -- Full/Historical Hourly Period
	PRINT 'Period Starting ' + CONVERT(varchar(32), @StartDate, 20) + ' To: ' + CONVERT(varchar(32), @EndDate, 20)
	/* Loop Through Equipment Records */
	FETCH FIRST FROM Equip_Cursor INTO @EquipTag, @InletFlowTag, @OutletFlowTag, @BrixTag, @MinFlow, @ActiveOrderID
	WHILE @@FETCH_STATUS = 0 AND @EndDate > @StartDate
		BEGIN -- Equipment Cursor Loop
		INSERT INTO dbo.kpiData
		(PeriodID, EquipTag, MinuteOffset, AvgInletGPM, AvgOutletGPM, AvgBrix, AvgLbPerGal, RunMins, AvailMins, OrderID)
		SELECT @PeriodID, @EquipTag, DateDiff(mi, @StartDate, DateTime) + @PeriodStatus AS MinuteOffset, 
		 AVG(CASE Tagname WHEN @InletFlowTag THEN Value ELSE Null END) As AvgInletGPM,
		 AVG(CASE Tagname WHEN @OutletFlowTag THEN Value ELSE Null END) As AvgOutletGPM,
		 AVG(CASE Tagname WHEN @BrixTag THEN Value ELSE Null END) As AvgBrix,
		 AVG((CASE Tagname WHEN @BrixTag THEN ISNULL(Value, 33.0) ELSE Null END) * 0.0043 + 1) * 8.3 As AvgLbPerGal,
		 SUM(CASE WHEN Tagname = @InletFlowTag AND Value > @MinFlow THEN 0.1 ELSE 0 END) As RunMins,
		 1.0 AS AvailMins,
		 @ActiveOrderID
		 FROM WW_INSQL_2.Runtime.dbo.History
		 WHERE History.TagName IN (@InletFlowTag, @OutletFlowTag , @BrixTag  )
		 AND wwRetrievalMode = 'Cyclic'
		 AND wwResolution = 6000
		 AND wwVersion = 'Latest'
		 AND DateTime >= @StartDate
		 AND DateTime < @EndDate
--		 AND QualityDetail = 192
		 GROUP BY  DateDiff(mi, @StartDate, DateTime) 		
		FETCH NEXT FROM Equip_Cursor INTO @EquipTag, @InletFlowTag, @OutletFlowTag, @BrixTag, @MinFlow, @ActiveOrderID
		END -- Equipment Cursor Loop
	/* If Inlet Value Was Null But Outlet Was Reading, Reflect Correct Run Minutes */
	IF EXISTS (SELECT * FROM dbo.kpiData WHERE (PeriodID = @PeriodID) AND (AvgInletGPM IS NULL))
		BEGIN -- Update Run Minutes
		UPDATE dbo.kpiData SET RunMins = 1.0
			WHERE (PeriodID = @PeriodID) AND (AvgInletGPM IS NULL) AND (AvgOutletGPM > (@MinFlow / 5.0))
		END -- Update Run Minutes
	/* Mark Period Completed */
	UPDATE dbo.kpiPeriods SET PeriodStatus = @PeriodMinute WHERE PeriodID = @PeriodID
	FETCH NEXT FROM Periods_Cursor INTO @PeriodID, @StartDate, @EndDate, @PeriodStatus
	END -- Periods Cursor Loop
	
CLOSE Equip_Cursor
DEALLOCATE Equip_Cursor

CLOSE Periods_Cursor
DEALLOCATE Periods_Cursor

--SELECT * FROM dbo.kpiData


GO
/****** Object:  StoredProcedure [dbo].[kpiDetermineDowntime]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[kpiDetermineDowntime] AS

SET NOCOUNT ON


DECLARE
	@System varchar(12),
	@LossCategory char(1),
	@NewLossCategory char(1),
	@LossRecordID int,
	@StartPeriodID int,
	@StartMinuteOffset int,
	@RateReference float

/*	
	Inserting into a temporary table to aggregate based off of Equipment ID. The select
	statement in the cursor loop below is grouped by system. The reason for this is because
	multi-part systems with more than one equipment need a double aggregate, a sum of the 2
	averages for proper calculation.  
*/
	
SELECT * INTO #TEMP FROM(
SELECT eq.EquipTag, MAX(eq.System) System, AVG(kd.lbs) Lbs, MAX(sy.YieldAdjust) YieldAdjust, MAX(sy.ProductionRate) ProductionRate, MAX(sy.LossCategory) LossCategory, MAX(sy.LossRecordID) LossRecordID, SUM(kd.RunMins) AS RunMins, SUM(kd.AvailMins) AS AvailMins FROM dbo.vkpiPeriodData kd
INNER JOIN dbo.kpiEquipment eq ON kd.EquipTag = eq.EquipTag
INNER JOIN vSystemsWithOrderAndLossRef sy ON sy.System = eq.System
WHERE kd.PeriodStart > DATEADD(hh, -2, getdate())
	AND kd.TimeStamp >  DATEADD(mi, -11, getdate())
	AND kd.TimeStamp < GETDATE()
GROUP BY eq.EquipTag) AS a

/* Find Availability Loss Events to Be Created */
DECLARE LossChecks CURSOR LOCAL FAST_FORWARD FOR
SELECT System, LossCategory, LossRecordID, 
	CASE
		-- 'A' = Availability Loss, 'P' = Performance Loss, 'N' = No Loss/Reset, 'S' = Idle/Transitioning
		WHEN Avail < 0.80 THEN 'A' 
		WHEN OEE / NULLIF(Avail, 0.0) < 0.90 THEN 'P'
		WHEN (Avail > 0.81) AND (OEE / NULLIF(Avail, 0.0) > 0.91) THEN 'N' 
		ELSE 'S' END AS NewLossCategory
FROM
	(SELECT System, LossCategory, LossRecordID, ((SUM(Lbs) * YieldAdjust) / (ProductionRate * 1000000.0 / 1440.0)) AS OEE, (SUM(RunMins) /SUM(AvailMins)) AS Avail
	FROM #TEMP
	GROUP BY System, LossCategory, LossRecordID, YieldAdjust, ProductionRate
	) dat

OPEN LossChecks

FETCH NEXT FROM LossChecks INTO @System, @LossCategory, @LossRecordID, @NewLossCategory

WHILE @@FETCH_STATUS = 0 
	BEGIN -- Cursor Loop
	IF @NewLossCategory <> 'N' AND @NewLossCategory <> 'S'
	BEGIN
		IF (@LossCategory IS NULL) OR (@LossCategory = 'P' AND @NewLossCategory = 'A')
			BEGIN
				/*	The datepart(minute, getdate()) function was used instead of the minute offset from the kpiData table because, as of now,
					the offset value is extrapolating up to 118, which is not correct. */
				SELECT @StartPeriodID = MAX(dat.PeriodID), @StartMinuteOffset = datepart(minute, getdate()) 
				FROM kpiData dat 
					INNER JOIN dbo.kpiEquipment eq on dat.EquipTag = eq.EquipTag
					WHERE eq.System = @System
				
				INSERT INTO kpiLossHistory (System, LossCategory, StartPeriodID, StartMinuteOffset, RateReference) 
				VALUES (@System, @NewLossCategory, @StartPeriodID, @StartMinuteOffset, 0 )
				
				UPDATE kpiSystems SET ActiveLossRecordID = SCOPE_IDENTITY() WHERE System = @System
			END
	END
	IF @NewLossCategory = 'N'
	BEGIN
		IF @LossCategory IS NOT NULL
		BEGIN
			UPDATE kpiSystems SET ActiveLossRecordID = NULL WHERE System = @System
		END
	END
	
	FETCH NEXT FROM LossChecks INTO @System, @LossCategory, @LossRecordID, @NewLossCategory
	END -- Curso Loop
CLOSE LossChecks
DEALLOCATE LossChecks
DROP TABLE #TEMP

GO
/****** Object:  Table [dbo].[kpiDashBoardSummary]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[kpiDashBoardSummary](
	[System] [varchar](12) NOT NULL,
	[SummaryLevel] [int] NOT NULL,
	[SummaryLevelText] [varchar](12) NULL,
	[OEE] [float] NOT NULL,
	[Availability] [float] NOT NULL,
	[Performance] [float] NOT NULL,
 CONSTRAINT [PK_kpiDashBoardSummary] PRIMARY KEY CLUSTERED 
(
	[System] ASC,
	[SummaryLevel] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[kpiData]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[kpiData](
	[PeriodID] [int] NOT NULL,
	[EquipTag] [varchar](12) NOT NULL,
	[MinuteOffset] [int] NOT NULL,
	[AvgInletGPM] [real] NULL,
	[AvgOutletGPM] [real] NULL,
	[AvgBrix] [real] NULL,
	[AvgLbPerGal] [real] NULL,
	[RunMins] [real] NULL,
	[AvailMins] [real] NULL,
	[OrderID] [int] NULL,
 CONSTRAINT [PK_kpiData] PRIMARY KEY CLUSTERED 
(
	[PeriodID] ASC,
	[EquipTag] ASC,
	[MinuteOffset] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[kpiEquipment]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[kpiEquipment](
	[EquipTag] [varchar](12) NOT NULL,
	[System] [varchar](12) NOT NULL,
	[InletFlowTag] [varchar](64) NOT NULL,
	[OutletFlowTag] [varchar](64) NULL,
	[BrixTag] [varchar](64) NULL,
	[MinFlow] [float] NULL,
 CONSTRAINT [PK_kpiEquipment] PRIMARY KEY CLUSTERED 
(
	[EquipTag] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[kpiLossHistory]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[kpiLossHistory](
	[LossRecordID] [int] IDENTITY(100000,1) NOT NULL,
	[System] [varchar](12) NOT NULL,
	[LossCategory] [char](1) NOT NULL,
	[StartPeriodID] [int] NOT NULL,
	[StartMinuteOffset] [int] NOT NULL,
	[RateReference] [float] NULL,
	[Reason1] [varchar](20) NULL,
	[Reason2] [varchar](20) NULL,
	[Comment] [varchar](130) NULL,
 CONSTRAINT [PK_kpiLossHistory_1] PRIMARY KEY CLUSTERED 
(
	[LossRecordID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[kpiOrders]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[kpiOrders](
	[OrderID] [int] IDENTITY(10000,1) NOT NULL,
	[System] [varchar](12) NOT NULL,
	[SAPOrderNumber] [int] NOT NULL,
	[SAPOrderRevNum] [int] NOT NULL,
	[MaterialID] [int] NOT NULL,
	[MaterialName] [varchar](60) NOT NULL,
	[ProductionRate] [float] NOT NULL,
	[SetupHours] [float] NOT NULL,
	[YieldAdjust] [float] NOT NULL,
	[OrderQty] [float] NOT NULL,
	[OrderStatus] [varchar](12) NOT NULL,
	[RevisionDate] [datetime] NOT NULL,
	[RevisionBy] [varchar](40) NULL,
 CONSTRAINT [PK_kpiOrders] PRIMARY KEY CLUSTERED 
(
	[OrderID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  Table [dbo].[kpiPeriods]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[kpiPeriods](
	[PeriodID] [int] NOT NULL,
	[PeriodStart] [datetime] NOT NULL,
	[PeriodEnd] [datetime] NOT NULL,
	[PeriodDate] [smalldatetime] NOT NULL,
	[PeriodStatus] [int] NULL,
	[PeriodShift] [int] NULL,
 CONSTRAINT [PK_kpiPeriods] PRIMARY KEY CLUSTERED 
(
	[PeriodID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[kpiSystems]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET ANSI_PADDING ON
GO
CREATE TABLE [dbo].[kpiSystems](
	[System] [varchar](12) NOT NULL,
	[TEEPRate] [float] NOT NULL,
	[ActiveLossRecordID] [int] NULL,
	[ActiveOrderID] [int] NULL,
	[YieldAdjust] [float] NOT NULL CONSTRAINT [DF_kpiSystems_YieldAdjust]  DEFAULT ((1.0)),
 CONSTRAINT [PK_kpiSystems] PRIMARY KEY CLUSTERED 
(
	[System] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING OFF
GO
/****** Object:  View [dbo].[vkpiPeriodData]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE VIEW [dbo].[vkpiPeriodData]
AS
SELECT     kp.PeriodDate, kp.PeriodStart, DATEADD(mi, kd.MinuteOffset, kp.PeriodStart) AS TimeStamp, kd.EquipTag, kd.MinuteOffset, kd.AvailMins, kd.RunMins, kd.AvgInletGPM, 
                      kd.AvgOutletGPM, kd.AvgBrix, CASE WHEN kd.RunMins = 0 THEN 0 ELSE CASE WHEN ke.BrixTag IS NULL 
                      THEN kd.AvgInletGPM * 8.5 ELSE kd.AvgOutletGPM * kd.AvgLbPerGal END END AS Lbs, kd.PeriodID
FROM         dbo.kpiPeriods AS kp INNER JOIN
                      dbo.kpiData AS kd ON kp.PeriodID = kd.PeriodID INNER JOIN
                      dbo.kpiEquipment AS ke ON ke.EquipTag = kd.EquipTag

GO
/****** Object:  View [dbo].[vkpiPeriodSummary]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[vkpiPeriodSummary] AS
SELECT 
	kd.PeriodDate, kd.PeriodStart, kd.EquipTag,
	SUM(kd.AvailMins) AS AvailMins, SUM(kd.RunMins) AS RunMins,
	SUM(kd.AvgInletGPM) AS InletGals, SUM(kd.AvgOutletGPM) AS OutletGals,
	AVG(kd.AvgBrix) AS AvgBrix, SUM(kd.Lbs) AS Lbs
	FROM dbo.vkpiPeriodData kd
	GROUP BY kd.PeriodDate, kd.PeriodStart, kd.EquipTag
	
GO
/****** Object:  View [dbo].[vInTouchSystemCurrentLoss]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE VIEW [dbo].[vInTouchSystemCurrentLoss] AS
SELECT sy.System
	, ISNULL(lh.LossRecordID, 0) AS LossRecordID
	, ISNULL(lh.LossCategory, '') AS LossCategory
	, ISNULL(CASE lh.LossCategory WHEN 'A' THEN 'Downtime' WHEN 'P' THEN 'Rate Loss' ELSE '' END, 'NONE') AS LossType
	, ISNULL(CONVERT(varchar(20), lh.LossStarted, 1) + ' ' + LEFT(CONVERT(varchar(20), lh.LossStarted, 8), 5), '') AS StartDateTime
	, ISNULL(DATEDIFF(mi, lh.LossStarted, getdate()), 0) AS LossMinutes
	, ISNULL(lh.LossReason, '') AS LossReason
	, ISNULL(lh.Comment, '') AS Comment
	, ISNULL(lh.Reason1, '') AS Reason1
	, ISNULL(lh.Reason2, '') AS Reason2
	FROM dbo.kpiSystems sy
	LEFT OUTER JOIN
		(SELECT	lh.LossRecordID
			, lh.LossCategory
			, DATEADD(mi, lh.StartMinuteOffset, kp.PeriodStart) AS LossStarted
			, ISNULL(lh.Reason1, '') + ISNULL('\' + lh.Reason2, '') AS LossReason
			, lh.Reason1
			, lh.Reason2
			, lh.Comment
			FROM dbo.kpiLossHistory lh
			INNER JOIN dbo.kpiPeriods kp ON lh.StartPeriodID = kp.PeriodID) lh
				on sy.ActiveLossRecordID = lh.LossRecordID

	

GO
/****** Object:  View [dbo].[vInTouchSystemOrders]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE VIEW [dbo].[vInTouchSystemOrders] AS
SELECT sy.System
	, ISNULL(ord.OrderID, '') AS OrderID
	, ISNULL(ord.SAPOrderNumber, 0) AS SAPOrderNumber
	, ISNULL(ord.SAPOrderRevNum, 0) AS SAPOrderRevNum
	, ISNULL(ord.MaterialID, 0) AS MaterialID
	, ISNULL(ord.MaterialName, '') AS MaterialName
	, ISNULL(ord.ProductionRate, 0.0) AS ProductionRate
	, ISNULL(ord.SetupHours, 0.0) AS SetupHours
	, ISNULL(ord.YieldAdjust, sy.YieldAdjust) AS YieldAdjust
	, ISNULL(ord.OrderQty, 0.0) AS OrderQty
	, ISNULL(ord.OrderStatus, 'OPEN') AS OrderStatus
	, ISNULL(ord.RevisionDate, GETDATE()) AS RevisionDate
	, ISNULL(ord.RevisionBy, '') AS RevisionBy
	FROM dbo.kpiSystems sy
	LEFT OUTER JOIN dbo.kpiOrders ord on sy.ActiveOrderID = ord.OrderID
	
GO
/****** Object:  View [dbo].[vSystemsWithOrderAndLossRef]    Script Date: 9/22/2016 2:43:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [dbo].[vSystemsWithOrderAndLossRef] AS
SELECT sy.system, ord.ProductionRate, ISNULL(ord.YieldAdjust, sy.YieldAdjust) AS YieldAdjust,
	lh.LossCategory, lh.Reason1, lh.RateReference, lh.LossRecordID
	FROM dbo.kpiSystems sy
	LEFT OUTER JOIN dbo.kpiOrders ord ON sy.ActiveOrderID = ord.OrderID
	LEFT OUTER JOIN dbo.kpiLossHistory lh ON sy.ActiveLossRecordID = lh.LossRecordID


GO
EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPane1', @value=N'[0E232FF0-B466-11cf-A24F-00AA00A3EFFF, 1.00]
Begin DesignProperties = 
   Begin PaneConfigurations = 
      Begin PaneConfiguration = 0
         NumPanes = 4
         Configuration = "(H (1[40] 4[20] 2[20] 3) )"
      End
      Begin PaneConfiguration = 1
         NumPanes = 3
         Configuration = "(H (1 [50] 4 [25] 3))"
      End
      Begin PaneConfiguration = 2
         NumPanes = 3
         Configuration = "(H (1 [50] 2 [25] 3))"
      End
      Begin PaneConfiguration = 3
         NumPanes = 3
         Configuration = "(H (4 [30] 2 [40] 3))"
      End
      Begin PaneConfiguration = 4
         NumPanes = 2
         Configuration = "(H (1 [56] 3))"
      End
      Begin PaneConfiguration = 5
         NumPanes = 2
         Configuration = "(H (2 [66] 3))"
      End
      Begin PaneConfiguration = 6
         NumPanes = 2
         Configuration = "(H (4 [50] 3))"
      End
      Begin PaneConfiguration = 7
         NumPanes = 1
         Configuration = "(V (3))"
      End
      Begin PaneConfiguration = 8
         NumPanes = 3
         Configuration = "(H (1[56] 4[18] 2) )"
      End
      Begin PaneConfiguration = 9
         NumPanes = 2
         Configuration = "(H (1 [75] 4))"
      End
      Begin PaneConfiguration = 10
         NumPanes = 2
         Configuration = "(H (1[66] 2) )"
      End
      Begin PaneConfiguration = 11
         NumPanes = 2
         Configuration = "(H (4 [60] 2))"
      End
      Begin PaneConfiguration = 12
         NumPanes = 1
         Configuration = "(H (1) )"
      End
      Begin PaneConfiguration = 13
         NumPanes = 1
         Configuration = "(V (4))"
      End
      Begin PaneConfiguration = 14
         NumPanes = 1
         Configuration = "(V (2))"
      End
      ActivePaneConfig = 0
   End
   Begin DiagramPane = 
      Begin Origin = 
         Top = 0
         Left = 0
      End
      Begin Tables = 
         Begin Table = "kp"
            Begin Extent = 
               Top = 6
               Left = 38
               Bottom = 114
               Right = 189
            End
            DisplayFlags = 280
            TopColumn = 0
         End
         Begin Table = "kd"
            Begin Extent = 
               Top = 6
               Left = 227
               Bottom = 114
               Right = 378
            End
            DisplayFlags = 280
            TopColumn = 0
         End
         Begin Table = "ke"
            Begin Extent = 
               Top = 114
               Left = 38
               Bottom = 222
               Right = 189
            End
            DisplayFlags = 280
            TopColumn = 0
         End
      End
   End
   Begin SQLPane = 
   End
   Begin DataPane = 
      Begin ParameterDefaults = ""
      End
   End
   Begin CriteriaPane = 
      Begin ColumnWidths = 11
         Column = 1440
         Alias = 900
         Table = 1170
         Output = 720
         Append = 1400
         NewValue = 1170
         SortType = 1350
         SortOrder = 1410
         GroupBy = 1350
         Filter = 1350
         Or = 1350
         Or = 1350
         Or = 1350
      End
   End
End
' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'vkpiPeriodData'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPaneCount', @value=1 , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'vkpiPeriodData'
GO
USE [master]
GO
ALTER DATABASE [KPIs] SET  READ_WRITE 
GO
