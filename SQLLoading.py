from sqlalchemy import create_engine
import mysql.connector
import pandas as pd
import numpy as np

# Importing the cleaned data
df_df = pd.read_csv('OlaData_Cleaned.csv')
# Setting up connection with MYSQL
username = "root"
password = "Secure$4u"
host = "localhost"
port = "3306"
database = "OLA_RIDES_ANALYSIS"

engine = create_engine(f"mysql+pymysql://{username}:{password}@{host}:{port}/{database}")

table_name = "OLA_RIDES_DATA"   # choose any table name
df_df.to_sql(table_name, engine , if_exists="replace", index=False)