# Updated get_txn_ocean.py with English comments

import requests
import json
from datetime import datetime, timedelta
import pandas as pd

# JSON-RPC configuration for Bitcoin node
rpc_user = "umbrel"
rpc_password = "umbrel"
rpc_url = "http://umbrel.local:8332/"

# Function to make RPC calls to the Bitcoin node
def bitcoin_rpc(method, params=None):
    headers = {"content-type": "application/json"}
    payload = json.dumps({"method": method, "params": params or [], "id": 1})
    response = requests.post(rpc_url, headers=headers, data=payload, auth=(rpc_user, rpc_password))
    print(response.json())
    return response.json()

# Check if the transaction input list contains a coinbase transaction
def contains_coinbase(vin_list_str):
    return "coinbase" in vin_list_str

# Check if the transaction output list contains OP_RETURN
def contains_op_return(vout_list_str):
    try:
        vout_list_str = vout_list_str.replace("'", "\"")  # Replace single quotes with double quotes
        vout_list = json.loads(vout_list_str)
        for output in vout_list:
            if "scriptPubKey" in output and "asm" in output["scriptPubKey"]:
                if "OP_RETURN" in output["scriptPubKey"]["asm"]:
                    return True
    except json.JSONDecodeError:
        print("JSONDecodeError: Check data format.")
    return False

# Analyze transactions to detect OP_RETURN, Ordinals, or Runes patterns
def analyze_transactions(row):
    vout = row['vout'].replace("'", "\"")
    vout_list = json.loads(vout)
    print(vout_list)
    for output in vout_list:
        script_pub_key = output['scriptPubKey']
        if 'asm' in script_pub_key and 'OP_RETURN' in script_pub_key['asm']:
            return "normal"  # Return "normal" if OP_RETURN is detected
    return is_ordinal_or_rune(row)

# Detect Ordinals and Runes patterns in a transaction
def is_ordinal_or_rune(tx):
    vin = tx['vin'].replace("'", "\"")
    vin_list = json.loads(vin)
    print(vin_list)
    for inputs in vin_list:
        if 'txinwitness' in inputs:
            for witness in inputs['txinwitness']:
                if len(witness) > 500:  # Length threshold based on empirical observation
                    return "ordinals"
    vout = tx['vout'].replace("'", "\"")
    vout_list = json.loads(vout)
    print(vout_list)
    for outputs in vout_list:
        script_pub_key = outputs['scriptPubKey']
        if 'asm' in script_pub_key:
            asm_script = script_pub_key['asm']
            if "OP_DUP OP_HASH160" not in asm_script and "OP_EQUALVERIFY OP_CHECKSIG" not in asm_script:
                if "OP_CHECKMULTISIG" not in asm_script and "witness_v0_keyhash" not in script_pub_key.get("type", ""):
                    if len(asm_script) > 100:
                        return "runes"
    return "normal"

def contains_coinbase(vin_list_str):
    if "coinbase" in vin_list_str:
        return True
    return False

def contains_op_return(vout_list_str):
    try:
        # If vout_list_str is already a list, skip the string conversion
        if isinstance(vout_list_str, list):
            vout_list = vout_list_str
        else:
            vout_list_str = vout_list_str.replace("'", "\"")  # Replace single quotes with double quotes
            vout_list = json.loads(vout_list_str)
        
        for output in vout_list:
            if "scriptPubKey" in output and "asm" in output["scriptPubKey"]:
                if "OP_RETURN" in output["scriptPubKey"]["asm"]:
                    return True
    except json.JSONDecodeError:
        print("JSONDecodeError: Check data format.")
    return False

# Run the transaction extraction and analysis process
def run():
    df_ocean_blocks = pd.read_csv("ocean_blocks.csv")
    blocks = df_ocean_blocks["Height"].unique().tolist()
    transactions = []
    for block_height in blocks:
        block_hash_data = bitcoin_rpc("getblockhash", [block_height])
        if block_hash_data:
            block_hash = block_hash_data['result']
            block_data = bitcoin_rpc("getblock", [block_hash, 2])
            if block_data:
                for tx in block_data['result']['tx']:
                    transactions.append(tx)

    # Convert transactions to a DataFrame
    df = pd.DataFrame(transactions)
    df["op_return"] = df['vout'].apply(contains_op_return)
    df["coinbase"] = df['vin'].apply(contains_coinbase)
    # Save transactions to CSV
    df.to_csv("ocean_tx.csv", index=False, encoding="utf-8")
    return

run()
