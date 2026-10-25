import psycopg2
import csv
from datetime import date

# Database connection parameters
DB_PARAMS = {
    "dbname": "your_db",
    "user": "your_user",
    "password": "your_password",
    "host": "localhost",
    "port": 5432
}

def generate_sample_data(filename):
    """Generate a sample CSV file for the COPY bulk load."""
    data = [
        (1, 101, 'Alice', '2024-01-15', 500.00),
        (2, 102, 'Bob', '2024-01-16', 1200.00),
        (3, 101, 'Alice', '2024-02-10', 150.00),
        (4, 103, 'Charlie', '2024-02-20', 2500.00)
    ]
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)
    print(f"Generated {filename}")

def setup_database(cursor):
    """Creates tables, range partitions, and indexes."""
    
    # 1. Dimension Table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS dim_customer (
            customer_id INT PRIMARY KEY,
            customer_name VARCHAR(100),
            last_updated DATE
        );
    """)

    # 2. Range Partitioned Fact Table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS fact_sales (
            sale_id INT,
            customer_id INT,
            sale_date DATE,
            amount DECIMAL(10, 2)
        ) PARTITION BY RANGE (sale_date);
    """)

    # Create Partitions
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS fact_sales_2024_01 
        PARTITION OF fact_sales FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
        
        CREATE TABLE IF NOT EXISTS fact_sales_2024_02 
        PARTITION OF fact_sales FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
    """)

    # 3. Composite and Partial Indexes
    cursor.execute("""
        -- Composite Index: Optimizes queries filtering by both customer and date
        CREATE INDEX IF NOT EXISTS idx_comp_cust_date 
        ON fact_sales (customer_id, sale_date);

        -- Partial Index: Optimizes queries looking specifically for high-value sales
        CREATE INDEX IF NOT EXISTS idx_partial_high_value 
        ON fact_sales (amount) WHERE amount > 1000.00;
    """)

    # Staging Table for Bulk Load
    cursor.execute("""
        CREATE TEMP TABLE stg_sales (
            sale_id INT,
            customer_id INT,
            customer_name VARCHAR(100),
            sale_date DATE,
            amount DECIMAL(10, 2)
        );
    """)
    print("Database schema and indexes created.")

def run_pipeline():
    csv_file = 'daily_sales.csv'
    generate_sample_data(csv_file)

    conn = psycopg2.connect(**DB_PARAMS)
    conn.autocommit = True
    cursor = conn.cursor()

    try:
        setup_database(cursor)

        # 4. COPY Bulk Load
        # Load raw CSV data directly into the staging table efficiently
        with open(csv_file, 'r') as f:
            cursor.copy_expert("COPY stg_sales FROM STDIN WITH CSV", f)
        print("Bulk load (COPY) completed.")

        # 5. MERGE on Dimension Table (SCD Type 1)
        # Update existing customers or insert new ones
        cursor.execute("""
            MERGE INTO dim_customer AS target
            USING (SELECT DISTINCT customer_id, customer_name FROM stg_sales) AS source
            ON target.customer_id = source.customer_id
            WHEN MATCHED THEN
                UPDATE SET customer_name = source.customer_name, last_updated = CURRENT_DATE
            WHEN NOT MATCHED THEN
                INSERT (customer_id, customer_name, last_updated)
                VALUES (source.customer_id, source.customer_name, CURRENT_DATE);
        """)
        print("MERGE on dimension table completed.")

        # 6. Load into Fact Table
        # Data will automatically route to the correct partition based on sale_date
        cursor.execute("""
            INSERT INTO fact_sales (sale_id, customer_id, sale_date, amount)
            SELECT sale_id, customer_id, sale_date, amount
            FROM stg_sales;
        """)
        print("Data loaded into range-partitioned fact table.")

    except Exception as e:
        print(f"Pipeline error: {e}")
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    run_pipeline()