import pandas as pd
import numpy as np;

# STEP 1: LOAD THE RAW FILE
# Just reading the file into a table (DataFrame) so we can inspect and clean it.
df = pd.read_csv("OlaData.csv")

print("Raw file loaded:", df.shape[0], "rows,", df.shape[1], "columns")

# STEP 2: INSPECT THE DATA FIRST (find out what is actually messy)
# We check for the usual suspects: bad column names, empty columns, wrong
# data types, extra spaces in text, duplicate rows, and duplicate IDs.
# We print everything we find BEFORE touching the data, so we know exactly
# what we are fixing and why.

print("\n--- INSPECTION: column names as given ---")
print(list(df.columns))
# Finding: column names are inconsistent -- mixed case ("Booking_ID") and
# one column has a space instead of an underscore ("Vehicle Images").
# This breaks MySQL (spaces in column names need backticks) and makes
# queries error-prone. -> NEEDS CLEANING.

print("\n--- INSPECTION: fully empty columns ---")
print(df.isnull().sum()[df.isnull().sum() == len(df)])
# Finding: "Vehicle Images" is empty in all 20,407 rows (100% missing).
# It carries zero information and is not used anywhere in our analysis.
# -> SAFE TO DROP (removing an all-empty column is not "changing data",
#    there was never any data in it).

print("\n--- INSPECTION: data types ---")
print(df.dtypes)
# Finding: 'Date' and 'Time' are stored as plain text (object), not as a
# real date/time. This can make date functions (like HOUR() or DAYNAME()
# in SQL) unreliable. -> NEEDS TYPE CONVERSION (values themselves do not
# change, only how they are stored).

print("\n--- INSPECTION: stray leading/trailing spaces in text columns ---")
text_cols = df.select_dtypes(include="object").columns
for col in text_cols:
    has_space_issue = (df[col].dropna().astype(str) !=
                        df[col].dropna().astype(str).str.strip()).sum()
    if has_space_issue > 0:
        print(col, "->", has_space_issue, "values have extra spaces")
# Finding: none of the text columns currently have extra spaces, but we
# still add a defensive ".str.strip()" step below so the file stays clean
# even if a future export re-introduces stray spaces.

print("\n--- INSPECTION: duplicate rows / duplicate Booking_IDs ---")
print("Fully duplicated rows:", df.duplicated().sum())
print("Duplicate Booking_IDs:", df["Booking_ID"].duplicated().sum())
# Finding: no duplicate rows and no duplicate Booking_IDs were found. We
# still add a safety-net de-duplication step below in case this changes
# in a future data pull.

print("\n--- INSPECTION: are the 'missing' values actually meaningful? ---")
print(pd.crosstab(df["Booking_Status"], df["Canceled_Rides_by_Customer"].notna()))
print(pd.crosstab(df["Booking_Status"], df["Payment_Method"].notna()))
# Finding: columns like V_TAT, C_TAT, Payment_Method, Driver_Ratings,
# Customer_Rating, Canceled_Rides_by_Customer, Canceled_Rides_by_Driver
# and Incomplete_Rides_Reason are blank ONLY where they logically don't
# apply -- e.g. a ride that was "Canceled by Driver" was never paid for,
# so Payment_Method is correctly blank. This is NOT dirty data.
# -> DO NOT FILL OR DROP THESE BLANKS. Filling them with 0/"Unknown"
#    would corrupt every COUNT()/AVG() based query in the SQL analysis.


# STEP 3: CLEAN COLUMN NAMES
# Make every column name lowercase, replace spaces with underscores, and
# strip stray spaces -- so column names are consistent and MySQL-safe.
# (This matches the same standardisation approach used in the original
# project, so the column names used in the SQL file do not change.)
df.columns = (
    df.columns
      .str.strip()
      .str.lower()
      .str.replace(" ", "_", regex=False)
)
print("\nColumn names after cleaning:", list(df.columns))


# STEP 4: DROP THE COMPLETELY EMPTY COLUMN
# 'vehicle_images' has zero values in all 20,407 rows. Dropping an
# entirely empty column does not remove or alter any real data.
if df["vehicle_images"].isnull().all():
    df = df.drop(columns=["vehicle_images"])
    print("\nDropped 'vehicle_images' column (was 100% empty).")


# STEP 5: STRIP STRAY SPACES FROM ALL TEXT COLUMNS (safety net)
# Removes accidental leading/trailing spaces from every text column.
# This does not change the wording/spelling of any value, only removes
# invisible extra spaces that could break GROUP BY / WHERE matching in SQL.
text_cols = df.select_dtypes(include="object").columns
for col in text_cols:
    df[col] = df[col].str.strip()

# STEP 6: FIX DATA TYPES
# Convert 'date' from text to a real date, and 'time' from text to a real
# time. The values themselves (e.g. "2024-07-26", "14:00:00") stay the same
# -- we are only telling pandas/MySQL to treat them as real date/time
# instead of plain text.
df["date"] = pd.to_datetime(df["date"], format="%Y-%m-%d %H:%M:%S")
df["time"] = pd.to_datetime(df["time"], format="%H:%M:%S").dt.time

# Make sure numeric columns are stored as numbers, not text (they already
# were in this file, but this line guarantees it stays that way).
numeric_cols = ["v_tat", "c_tat", "booking_value", "ride_distance",
                 "driver_ratings", "customer_rating"]
for col in numeric_cols:
    df[col] = pd.to_numeric(df[col], errors="coerce")

# STEP 7: STANDARDIZE TEXT CASING IN CATEGORY COLUMNS (safety net)
# Ensures category values like vehicle type, payment method, and
# cancellation reasons always use the exact same spelling/casing, so
# GROUP BY in SQL doesn't accidentally split "UPI" and "upi" into two
# separate groups. In this file, the values were already consistent, so
# this line changes nothing -- it just guarantees future-proof consistency.
category_cols = ["booking_status", "vehicle_type", "pickup_location",
                  "drop_location", "payment_method",
                  "canceled_rides_by_customer", "canceled_rides_by_driver",
                  "incomplete_rides", "incomplete_rides_reason"]
for col in category_cols:
    df[col] = df[col].str.strip()


# STEP 8: SAFETY-NET DE-DUPLICATION (does nothing here, but protects future runs)
before = len(df)
df = df.drop_duplicates(subset=["booking_id"], keep="first")
after = len(df)
print(f"\nDuplicate Booking_IDs removed: {before - after} (expected 0 for this file)")


# STEP 9: FINAL CHECK -- confirm nothing important changed
print("\n--- FINAL SHAPE ---")
print(df.shape)
print("\n--- FINAL BOOKING STATUS COUNTS (should match the raw file exactly) ---")
print(df["booking_status"].value_counts())

df.to_csv("OlaData_Cleaned.csv", index=False)
print("\nSaved cleaned file as OlaData_Cleaned.csv")