"""
Project 1: NHS Maternity Outcomes Analysis
==========================================
Generates synthetic MSDS v2.0 data and runs key analytical queries.
Author: Joel Mokolo
Date:   2025-06

Run: python3 msds_analysis.py
Output: data/msds_2024_25_synthetic.csv and printed query results.
"""

import pandas as pd
import numpy as np
import sqlite3
import random
import os

np.random.seed(42)
random.seed(42)
N = 2000

# ── Trust reference (real NHS codes) ─────────────────────
trusts = [
    ("RR7", "Newcastle upon Tyne Hospitals NHS FT",         "North East and North Cumbria"),
    ("RXP", "County Durham and Darlington NHS FT",          "North East and North Cumbria"),
    ("RNN", "Northumbria Healthcare NHS FT",                "North East and North Cumbria"),
    ("RVW", "North Tees and Hartlepool NHS FT",             "North East and North Cumbria"),
    ("RTF", "Gateshead Health NHS FT",                      "North East and North Cumbria"),
    ("RHQ", "Sheffield Teaching Hospitals NHS FT",          "South Yorkshire and Bassetlaw"),
    ("RR8", "Leeds Teaching Hospitals NHS FT",              "West Yorkshire"),
    ("RGT", "Cambridge University Hospitals NHS FT",        "East of England"),
    ("RJ1", "Guy's and St Thomas' NHS FT",                  "South East London"),
    ("RA7", "University Hospitals Bristol NHS FT",          "Bristol, North Somerset and South Glos"),
]
trust_codes   = [t[0] for t in trusts]
trust_names   = {t[0]: t[1] for t in trusts}
trust_lmns    = {t[0]: t[2] for t in trusts}

# Booking behaviour varies by trust (mean weeks, std dev)
booking_params = {
    "RR7":(9.2,3.1), "RXP":(10.5,4.0), "RNN":(9.0,2.8),
    "RVW":(11.2,4.5), "RTF":(9.5,3.0), "RHQ":(10.0,3.8),
    "RR8":(9.3,3.2), "RGT":(8.8,2.9), "RJ1":(10.8,4.2), "RA7":(9.9,3.6),
}

eth_codes  = ["A","B","C","H","J","K","N","P","M","Z"]
eth_labels = ["White British","White Irish","White Other","Asian-Indian","Asian-Pakistani",
              "Asian-Bangladeshi","Black Caribbean","Black African","Mixed W+BC","Not stated"]
eth_wts    = [0.72,0.03,0.05,0.04,0.05,0.02,0.02,0.03,0.01,0.03]
eth_map    = dict(zip(eth_codes, eth_labels))

delivery_opts = ["Spontaneous Vaginal","Elective CS","Emergency CS","Instrumental","Unspecified"]
delivery_wts  = [0.44, 0.20, 0.25, 0.10, 0.01]
smoking_opts  = ["Smoker","Non-smoker","Ex-smoker","Not recorded"]
smoking_wts   = [0.12, 0.72, 0.08, 0.08]
bf_opts       = ["Breast milk","Formula","Mixed","Not recorded"]
bf_wts        = [0.48, 0.36, 0.08, 0.08]
months        = pd.date_range("2024-04-01","2025-03-31",freq="MS")
trust_vols    = [200,180,170,150,120,200,200,280,280,170]


def generate_dataset(n: int) -> pd.DataFrame:
    """Generate n synthetic MSDS records with realistic variation and quality gaps."""
    rows = []
    for i in range(n):
        tc  = random.choices(trust_codes, weights=trust_vols)[0]
        eth = random.choices(eth_codes,   weights=eth_wts)[0]
        imd = random.choices(range(1,11), weights=[0.15,0.13,0.12,0.11,0.10,0.10,0.09,0.08,0.07,0.05])[0]

        mu, sigma = booking_params[tc]
        bw = round(np.clip(np.random.normal(mu, sigma), 4.0, 40.0), 1)
        bw = None if random.random() < 0.08 else bw          # ~8% missing

        dm   = random.choices(delivery_opts, weights=delivery_wts)[0]
        sm   = random.choices(smoking_opts,  weights=smoking_wts)[0]
        bf   = random.choices(bf_opts,       weights=bf_wts)[0]
        age  = int(np.clip(np.random.normal(30.5, 5.8), 16, 52))
        gest = int(np.clip(np.random.normal(39.2, 2.4), 22, 44))
        gest = None if random.random() < 0.05 else gest       # ~5% missing
        bwt  = max(400, round(np.random.normal(3350, 520)))
        eth  = None if random.random() < 0.03 else eth        # ~3% missing
        mon  = random.choice(months)

        rows.append({
            "record_id":           f"MSDS{i+1:05d}",
            "report_period_month": mon.strftime("%Y-%m"),
            "trust_code":          tc,
            "trust_name":          trust_names[tc],
            "lmns":                trust_lmns[tc],
            "maternal_age":        age,
            "ethnicity_code":      eth,
            "ethnicity_desc":      eth_map.get(eth) if eth else None,
            "imd_decile":          imd,
            "booking_week":        bw,
            "booked_by_10_weeks":  (1 if bw <= 10 else 0) if bw is not None else None,
            "delivery_method":     dm,
            "gestation_weeks":     gest,
            "preterm":             ("Y" if gest < 37 else "N") if gest else None,
            "birthweight_grams":   bwt,
            "low_birthweight":     "Y" if bwt < 2500 else "N",
            "smoking_at_delivery": sm,
            "first_feed_type":     bf,
        })
    return pd.DataFrame(rows)


def run_analysis(conn: sqlite3.Connection) -> None:
    """Run core analytical queries and print formatted results."""

    queries = {
        "Q1 — Field completeness by trust": """
            SELECT trust_code,
                   COUNT(*) AS total,
                   ROUND(SUM(CASE WHEN booking_week    IS NOT NULL THEN 1.0 ELSE 0 END)*100/COUNT(*),1) AS bk_wk_pct,
                   ROUND(SUM(CASE WHEN gestation_weeks IS NOT NULL THEN 1.0 ELSE 0 END)*100/COUNT(*),1) AS gest_pct,
                   ROUND(SUM(CASE WHEN ethnicity_code  IS NOT NULL THEN 1.0 ELSE 0 END)*100/COUNT(*),1) AS eth_pct,
                   ROUND(SUM(CASE WHEN smoking_at_delivery != 'Not recorded' THEN 1.0 ELSE 0 END)*100/COUNT(*),1) AS smoke_pct
            FROM msds_episodes GROUP BY trust_code ORDER BY bk_wk_pct ASC
        """,
        "Q2 — Booking within 10 weeks (CNST KPI) by trust": """
            SELECT trust_code, COUNT(*) AS total,
                   ROUND(SUM(CASE WHEN booked_by_10_weeks=1 THEN 1.0 ELSE 0 END)*100/
                         NULLIF(SUM(CASE WHEN booking_week IS NOT NULL THEN 1.0 ELSE 0 END),0),1) AS pct_early,
                   SUM(CASE WHEN booking_week IS NULL THEN 1 ELSE 0 END) AS missing_bk
            FROM msds_episodes GROUP BY trust_code ORDER BY pct_early ASC
        """,
        "Q3 — Delivery method distribution": """
            SELECT delivery_method, COUNT(*) AS n,
                   ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM msds_episodes),1) AS pct
            FROM msds_episodes GROUP BY delivery_method ORDER BY n DESC
        """,
        "Q4 — Preterm rate by deprivation band": """
            SELECT CASE WHEN imd_decile BETWEEN 1 AND 3 THEN 'Most deprived 1-3'
                        WHEN imd_decile BETWEEN 4 AND 7 THEN 'Mid 4-7'
                        ELSE 'Least deprived 8-10' END AS deprivation,
                   COUNT(*) AS total,
                   ROUND(SUM(CASE WHEN preterm='Y' THEN 1.0 ELSE 0 END)*100/COUNT(*),1) AS preterm_pct
            FROM msds_episodes WHERE gestation_weeks IS NOT NULL GROUP BY 1 ORDER BY preterm_pct DESC
        """,
        "Q5 — Smoking at delivery by trust": """
            SELECT trust_code,
                   SUM(CASE WHEN smoking_at_delivery='Smoker' THEN 1 ELSE 0 END) AS smokers,
                   ROUND(SUM(CASE WHEN smoking_at_delivery='Smoker' THEN 1.0 ELSE 0 END)*100/
                         NULLIF(SUM(CASE WHEN smoking_at_delivery!='Not recorded' THEN 1.0 ELSE 0 END),0),1) AS smoker_pct
            FROM msds_episodes GROUP BY trust_code ORDER BY smoker_pct DESC
        """,
        "Q6 — Monthly trend: early booking and emergency CS rates": """
            SELECT report_period_month,
                   COUNT(*) AS episodes,
                   ROUND(SUM(CASE WHEN booked_by_10_weeks=1 THEN 1.0 ELSE 0 END)*100/
                         NULLIF(SUM(CASE WHEN booking_week IS NOT NULL THEN 1.0 ELSE 0 END),0),1) AS early_bk_pct,
                   ROUND(SUM(CASE WHEN delivery_method='Emergency CS' THEN 1.0 ELSE 0 END)*100/COUNT(*),1) AS emcs_pct
            FROM msds_episodes GROUP BY report_period_month ORDER BY report_period_month
        """,
    }

    for title, sql in queries.items():
        print(f"\n{'='*60}")
        print(f"  {title}")
        print('='*60)
        df = pd.read_sql(sql, conn)
        print(df.to_string(index=False))


if __name__ == "__main__":
    os.makedirs("data", exist_ok=True)

    print("Generating synthetic MSDS dataset...")
    df = generate_dataset(N)
    df.to_csv("data/msds_2024_25_synthetic.csv", index=False)
    print(f"  Saved {len(df)} rows to data/msds_2024_25_synthetic.csv")

    print("\nLoading into SQLite database...")
    conn = sqlite3.connect("data/msds.db")
    df.to_sql("msds_episodes", conn, if_exists="replace", index=False)
    df[["trust_code","trust_name","lmns"]].drop_duplicates().to_sql(
        "dim_trust", conn, if_exists="replace", index=False
    )
    print("  Loaded msds_episodes and dim_trust tables.")

    print("\nRunning analysis queries...")
    run_analysis(conn)
    conn.close()

    print("\n\nAnalysis complete.")
    print("Next step: Open Power BI and connect to data/msds_2024_25_synthetic.csv")
    print("           to build the KPI dashboard (Project 2).")
