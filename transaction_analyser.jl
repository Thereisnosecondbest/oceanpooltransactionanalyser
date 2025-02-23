using HTTP
using JSON3
using DataFrames
using CSV
# ========== RPC 설정 ==========
const rpc_user = "umbrel"
const rpc_password = "umbrel"
const rpc_host = "umbrel.local"
const rpc_port = "8332"
const rpc_url = "http://$rpc_user:$rpc_password@$rpc_host:$rpc_port"

# ========== Knots 정책 설정 ==========
const MAX_STANDARD_P2WSH_SCRIPT_SIZE = 3600  # Witness 크기 제한
const MAX_STANDARD_P2WSH_STACK_ITEM_SIZE = 80  # Witness 스택 아이템 크기 제한
const MAX_STANDARD_TAPSCRIPT_STACK_ITEM_SIZE = 80  # Taproot Witness 제한
const DEFAULT_REJECT_TOKENS = true  # Runes/Ordinals 필터링 활성화

# ========== HEX -> Bytes ==========
function hex2bytes(hex_str::String)
    if startswith(hex_str, "0x")
        hex_str = hex_str[3:end]
    end
    n = length(hex_str)
    if isodd(n)
        throw(ArgumentError("홀수 개의 hex 숫자 발견: $hex_str"))
    end
    data = Vector{UInt8}(undef, div(n, 2))
    @inbounds for i in 1:2:n
        data[(i+1) >>> 1] = parse(UInt8, hex_str[i:i+1], base=16)
    end
    return data
end

# ========== 간단 JSON 파싱 (Ordinals/BRC-20) ==========
function try_parse_json(str_data::AbstractString)
    try
        return JSON3.read(str_data)
    catch
        return nothing
    end
end

# -----------------------------------------------------------------
# (A) ordiscan 유사 Runes 바이너리 파서 (가정)
# -----------------------------------------------------------------
"""
    parse_runes_protocol(data::Vector{UInt8})

가상의 Runes 프로토콜 파서:
1) 2바이트 매직 (0xd6, 0x89) 확인  
2) 1바이트 버전 (예: 0x01) 확인  
3) 이후 TLV (tag, length, value) 형식의 데이터를 순차적으로 파싱

* 주의: 실제 구현시 ordiscan 코드나 Runes 문서를 참고하여 정밀하게 구현해야 합니다.
"""
function parse_runes_protocol(data::Vector{UInt8})
    # 최소 길이: 매직(2) + 버전(1) = 3바이트
    if length(data) < 3
        return false
    end

    # (1) 매직바이트 확인
    if data[1] != 0xd6 || data[2] != 0x89
        return false
    end

    # (2) 버전 확인 (예: 0x01)
    version = data[3]
    if version != 0x01
        return false
    end

    # (3) TLV 파싱: 모든 필드를 문제없이 읽어야 성공으로 간주
    i = 4
    while i <= length(data)
        # tag와 length를 읽을 수 있는지 확인
        if i + 1 > length(data)
            return false
        end
        tag = data[i]
        len = data[i+1]
        i += 2
        # value의 길이가 충분한지 확인
        if i + len - 1 > length(data)
            return false
        end
        # 필요시 value 처리: value = data[i : i+len-1]
        i += len
    end

    return true
end

"""
    is_runes_data_binary(data_bytes::Vector{UInt8})

실제 Runes 스펙(가정)에 따라 바이너리 데이터를 해석.
"""
function is_runes_data_binary(data_bytes::Vector{UInt8})
    return parse_runes_protocol(data_bytes)
end

# -----------------------------------------------------------------
# (B) 평문 JSON 내 Runes 여부 확인 ("p":"rune" 등)
# -----------------------------------------------------------------
function is_runes_data_json(data_str::AbstractString)
    j = try_parse_json(data_str)
    if j === nothing
        # JSON 파싱 실패 시 단순 문자열 검색
        if occursin("\"p\":\"rune\"", data_str) || occursin("\"p\":\"runes\"", data_str)
            return true
        else
            return false
        end
    end

    if j isa AbstractDict
        possible_keys = ["p", "protocol", "type", "app"]
        possible_vals = ["rune", "runes", "Rune", "Runes"]
        for k in possible_keys
            if haskey(j, k)
                val = j[k]
                if val isa String && (val in possible_vals)
                    return true
                end
            end
        end
        return false
    else
        # 배열 등일 경우 문자열로 변환해 검사
        j_str = String(JSON3.write(j))
        return occursin("\"p\":\"rune\"", j_str) || occursin("\"p\":\"runes\"", j_str)
    end
end

"""
    is_runes_data(data_str)

바이너리 파서와 JSON 탐지를 결합하여 Runes 데이터 여부 판별
"""
function is_runes_data(data_str::AbstractString)
    data_bytes = Vector{UInt8}(codeunits(data_str))
    # 1) 바이너리 데이터 판별
    if is_runes_data_binary(data_bytes)
        return true
    end
    # 2) 평문 JSON 검사
    return is_runes_data_json(data_str)
end

# -----------------------------------------------------------------
# (C) Ordinals / BRC-20 데이터 검사
# -----------------------------------------------------------------
function is_ordinals_data(data_str::AbstractString)
    j = try_parse_json(data_str)
    if j === nothing
        if occursin("\"p\":\"ord\"", data_str) || occursin("\"op\":\"mint\"", data_str)
            return "Ordinals (BRC-20)"
        elseif startswith(data_str, "PNG") || startswith(data_str, "\xFF\xD8\xFF")
            return "Ordinals (image)"
        elseif isascii(data_str)
            return "Ordinals (text?)"
        else
            return nothing
        end
    else
        if j isa AbstractDict
            if (haskey(j, "p") && j["p"] == "ord") || (haskey(j, "op") && j["op"] == "mint")
                return "Ordinals (BRC-20 가능성)"
            end
        else
            j_str = String(JSON3.write(j))
            if occursin("\"p\":\"ord\"", j_str) || occursin("\"op\":\"mint\"", j_str)
                return "Ordinals (BRC-20 가능성)"
            end
        end
    end
    return nothing
end



# -----------------------------------------------------------------
# (D) JSON-RPC 함수
# -----------------------------------------------------------------
function rpc_call(method, params=[])
    headers = ["Content-Type" => "application/json"]
    body = JSON3.write(Dict("jsonrpc" => "1.0", "id" => "julia",
                            "method" => method, "params" => params))
    response = HTTP.post(rpc_url, headers, body)
    # 응답 body를 문자열로 변환하여 JSON 파싱
    return JSON3.read(String(response.body))
end

function get_mempool_txids()
    result = rpc_call("getrawmempool")
    return result["result"]
end

function get_transaction(txid::String)
    result = rpc_call("getrawtransaction", [txid, true])
    return result["result"]
end

# -----------------------------------------------------------------
# (E) 최종 판별: check_ordinals_runes
# -----------------------------------------------------------------
function check_ordinals_runes(tx)
    # 1) vin 내 txinwitness 검사
    witness_filtered = false
    println(tx["txid"])
    if haskey(tx, "vin")
        for vin in tx["vin"]
            if haskey(vin, "txinwitness")
                for witness in vin["txinwitness"]
                    witness_filtered = !is_witness_standard(vin["txinwitness"])
                    if witness isa String && length(witness) >= 2
                        decoded_str = try
                            String(hex2bytes(witness))
                        catch e
                            # 디코딩 실패 시 (필요시 e 출력)
                            # println("Witness 디코딩 에러: $e")
                            nothing
                        end
                        if decoded_str !== nothing
                            # Ordinals 판별
                            ord_check = is_ordinals_data(decoded_str)
                            if ord_check !== nothing
                                return ord_check, witness_filtered
                            end
                            # Runes 판별
                            if is_runes_data(decoded_str)
                                return "Runes (Taproot)", witness_filtered
                            end
                        end
                    end
                end
            end
        end
    end

    # 2) vout 내 scriptPubKey.asm 의 OP_RETURN 검사
    if haskey(tx, "vout")
        for vout in tx["vout"]
            if haskey(vout, "scriptPubKey") && haskey(vout["scriptPubKey"], "asm")
                asm = vout["scriptPubKey"]["asm"]
                asm_tokens = split(asm)
                if "OP_RETURN" in asm_tokens
                    # 마지막 토큰을 HEX 데이터로 가정
                    data_hex = asm_tokens[end]
                    decoded_str = try
                        String(hex2bytes(data_hex))
                    catch
                        # 디코딩 실패 시 원본 HEX 문자열 사용
                        data_hex
                    end

                    # Runes 판별
                    if is_runes_data(decoded_str)
                        return "Runes (OP_RETURN)", witness_filtered
                    end

                    # Ordinals 판별
                    ord_check = is_ordinals_data(decoded_str)
                    if ord_check !== nothing
                        return ord_check, witness_filtered
                    end
                end
            end
        end
    end

    return "Regular", witness_filtered
end


# CSV 파일 읽기
function read_csv_transactions(file_path)
    df = CSV.read(file_path, DataFrame)
    println("CSV 열 이름: ", names(df))  # CSV의 실제 열 이름 출력
    return df
end

function fix_python_json(json_str::String)
    json_str = replace(json_str, "'" => "\"")  # 작은따옴표 → 큰따옴표
    json_str = replace(json_str, "[ALL]" => "")  # JSON에서 유효하지 않은 부분 제거
    json_str = strip(json_str)  # 앞뒤 공백 제거
    return json_str
end

# 안전한 JSON 변환 함수
function safe_parse_json(json_str::String)
    fixed_str = fix_python_json(json_str)
    #println(JSON3.read(fixed_str))
    try
        return JSON3.read(fixed_str)  # JSON3로 변환
    catch e
        println("JSON 변환 실패: ", fixed_str)
        return []
    end
end

# ========== Witness 필터링 함수 ==========
function is_witness_standard(tx_witness_stack)
    if tx_witness_stack === nothing || length(tx_witness_stack) == 0
        return true  # Witness 데이터가 없으면 기본적으로 허용
    end

    total_witness_size = sum(length(hex2bytes(witness)) for witness in tx_witness_stack)

    if total_witness_size > MAX_STANDARD_P2WSH_SCRIPT_SIZE
        return false  # 전체 Witness 크기가 제한 초과
    end

    for witness in tx_witness_stack
        if length(hex2bytes(witness)) > MAX_STANDARD_P2WSH_STACK_ITEM_SIZE
            return false  # 개별 Witness 요소 크기 초과
        end
    end

    return true
end

# ========== 트랜잭션 분석 ==========
function analyze_transaction(tx)
    txid = tx["txid"]

    # Witness 필터링 여부 확인
    witness_filtered = false
    # Runes / Ordinals 필터링 여부 확인
    runes_filtered = false
    ordinals_filtered = false

    if haskey(tx, "vin")
        for vin in tx["vin"]
            if haskey(vin, "txinwitness")
                witness_filtered = !is_witness_standard(vin["txinwitness"])
                if is_runes_data(vin["txinwitness"])
                    runes_filtered = true
                end
                if is_ordinals_data(vin["txinwitness"]) !== nothing
                    ordinals_filtered = true
                end
            end
        end
    end

    if haskey(tx, "vout")
        for vout in tx["vout"]
            if haskey(vout, "scriptPubKey") && haskey(vout["scriptPubKey"], "hex")
                script_pubkey = vout["scriptPubKey"]["hex"]
                if is_runes_data(script_pubkey)
                    runes_filtered = true
                end
                if is_ordinals_data(script_pubkey) !== nothing
                    ordinals_filtered = true
                end
            end
        end
    end

    return (txid, witness_filtered, runes_filtered, ordinals_filtered)
end

# 각 트랜잭션에서 Ordinals & Runes 판별
function analyze_transactions(df)
    results = DataFrame(txid = String[], category = String[], witness_filtered = Bool[], op_return = Bool[], coinbase = Bool[])

    for row in eachrow(df)
        txid = row.txid
        raw_tx = row.hex  # 기존 raw_transaction → hex로 변경
        op_return = row.op_return 
        coinbase = row.coinbase
        # vin, vout을 JSON으로 변환 (예외 처리 포함)
        vin = safe_parse_json(row.vin)
        vout = safe_parse_json(row.vout)
        # 트랜잭션 객체 생성
        tx = Dict(
            "txid" => txid,
            "vin" => vin,
            "vout" => vout,
            "op_return" => op_return,
            "coinbase" => coinbase,
        )
        
        # 트랜잭션을 JSON으로 변환
        #tx = decode_raw_transaction(raw_tx)
        if tx === nothing
            println("TXID $txid: 트랜잭션 디코딩 실패")
            continue
        end

        # 분석 실행
        category, witness_filtered = check_ordinals_runes(tx)
        push!(results, (txid, category, witness_filtered, op_return, coinbase))
    end

    return results
end



# Raw HEX 트랜잭션을 JSON으로 변환
function decode_raw_transaction(raw_tx::String)
    try
        result = rpc_call("decoderawtransaction", [raw_tx])
        return result["result"]
    catch
        return nothing  # 변환 실패 시 nothing 반환
    end
end

# 결과 저장
function save_results(results_df, output_path)
    CSV.write(output_path, results_df)
    println("결과가 저장되었습니다: $output_path")
end

# 실행
# CSV 파일 경로
const csv_file = "ocean_tx.csv"

df = read_csv_transactions(csv_file)
results_df = analyze_transactions(df)

# 결과 저장 (예제 파일명: output.csv)
output_file = "output.csv"
save_results(results_df, output_file)