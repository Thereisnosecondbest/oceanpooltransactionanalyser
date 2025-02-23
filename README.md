# 🔗 Ocean Mining Block Scraper & Transaction Analyzer

## 📌 Overview

This repository contains three integrated tools designed for scraping and analyzing Bitcoin blocks mined by the [Ocean Mining Pool](https://ocean.xyz):

1. **Ocean Mining Scraper (Python)**

   - Scrapes block data directly from the Ocean Mining Pool until a specified block height is reached.
   - Saves block details into a CSV file for further analysis.

2. **Ocean Transaction Extractor (Python)**

   - Fetches detailed transaction data from blocks scraped from Ocean Mining Pool.
   - Uses Bitcoin Knots node via JSON-RPC to extract transaction data from specified blocks.

3. **Ocean Block Transaction Analyzer (Julia)**

   - Analyzes block transactions mined by the Ocean Mining Pool.
   - Detects and filters transactions related to **Runes** and **Ordinals** protocols.
   - Applies Bitcoin Knots policy settings for witness size and mempool filtering.

---

## 🚀 Features

### ✅ Ocean Mining Scraper (Python)

- Automatically scrapes block data until a target block height is reached.
- Extracts block details such as:
  - DateTime
  - Shares
  - Difficulty
  - Address
  - Worker
  - Height
  - Block Hash
- Stores results into a CSV file.

### ✅ Ocean Transaction Extractor (Python)

- Connects to a Bitcoin Knots node via JSON-RPC.
- Fetches transaction details from scraped block heights.
- Saves transaction data into a CSV file.

### ✅ Ocean Block Transaction Analyzer (Julia)

- Detects:
  - **Runes** transactions through binary protocol analysis.
  - **Ordinals** transactions through witness and output script analysis.
- Filters transactions based on:
  - Witness stack size constraints (Knots policy)
  - Presence of Runes and Ordinals protocols
- Saves filtered results into a CSV file.

---

## 💻 Installation

### Prerequisites

Ensure you have the following installed:

- **Python 3.9+** (for scraper and transaction extractor)
- **Julia 1.6+** (for transaction analysis)
- A running **Bitcoin Knots full node** with RPC enabled.

### 🔗 Python Dependencies

Install necessary libraries using `pip`:

```bash
pip install requests beautifulsoup4 pandas
```

### 🔗 Julia Dependencies

Install required packages in Julia:

```julia
using Pkg
Pkg.add(["HTTP", "JSON3", "DataFrames", "CSV"])
```

---

## ⚙️ Usage

### 🔍 Step 1: Scrape Ocean Mining Blocks (Python)

1. Run the scraper to fetch block data until a specific block height:

```bash
python get_ocean_blocks.py
```

2. Configuration: Set your target block height inside `get_ocean_blocks.py`:

```python
scrape_ocean_until_block(target_block=819242, output_csv='ocean_blocks.csv')
```

3. Output: The scraper will generate a `ocean_blocks.csv` containing:

- `DateTime`
- `Shares`
- `Difficulty`
- `Address`
- `Worker`
- `Height`
- `BlockHash`

### 🔍 Step 2: Extract Transactions from Scraped Blocks (Python)

1. Run the transaction extractor:

```bash
python get_txn_ocean.py
```

2. Output: A CSV file named `ocean_tx.csv` will be generated with transaction details from the specified blocks.

### 🔍 Step 3: Analyze Transactions for Runes and Ordinals (Julia)

1. Configure your RPC settings in `transaction_analyser.jl`:

```julia
const rpc_user = "your_rpc_user"  # Replace with your Bitcoin Knots RPC username
const rpc_password = "your_rpc_password"  # Replace with your Bitcoin Knots RPC password
const rpc_host = "localhost"  # Replace with your node's host address
const rpc_port = "8332"  # Replace with your RPC port
```

2. Run the analysis script:

```bash
julia transaction_analyser.jl
```

3. Output: The analysis results will be saved as `output.csv` with:

- `txid`: Transaction ID
- `category`: Detected type (`Runes`, `Ordinals`, `Regular`)
- `witness_filtered`: Boolean flag indicating whether the witness size exceeded the threshold

---

## 📊 Workflow Summary

1. **Scrape blocks mined by Ocean Pool** → Use Python to collect block information.
2. **Fetch transaction details** → Use Python to retrieve transaction data from the Bitcoin Knots node.
3. **Analyze transactions** → Use Julia to detect Runes and Ordinals transactions based on witness size and other criteria.
4. **Save analysis results** → Export filtered transactions into a CSV file for review.

---

## 🤝 Contributing

Contributions are welcome! Please submit a pull request or open an issue for feature requests or bug reports.

---

## 📜 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.
