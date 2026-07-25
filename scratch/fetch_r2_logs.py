import hmac
import hashlib
import datetime
import urllib.request
import urllib.parse
import sys
import os
import xml.etree.ElementTree as ET

def sign(key, msg):
    return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()

def get_signature_key(key, date_stamp, regionName, serviceName):
    kDate = sign(('AWS4' + key).encode('utf-8'), date_stamp)
    kRegion = sign(kDate, regionName)
    kService = sign(kRegion, serviceName)
    kSigning = sign(kService, 'aws4_request')
    return kSigning

def aws_sigv4_request(method, host, bucket, key, access_key, secret_key, query_params=None, body=b""):
    t = datetime.datetime.utcnow()
    amz_date = t.strftime('%Y%m%dT%H%M%SZ')
    date_stamp = t.strftime('%Y%m%d')
    
    encoded_key = "/".join(urllib.parse.quote(seg, safe='') for seg in key.split('/'))
    if bucket:
        canonical_uri = f"/{bucket}/{encoded_key}"
    else:
        canonical_uri = f"/{encoded_key}" if key else "/"
        
    if query_params:
        canonical_querystring = "&".join(f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(v, safe='')}" for k, v in sorted(query_params.items()))
    else:
        canonical_querystring = ""
        
    body_hash = hashlib.sha256(body).hexdigest()
    
    canonical_headers = f"host:{host}\nx-amz-content-sha256:{body_hash}\nx-amz-date:{amz_date}\n"
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    
    canonical_request = f"{method}\n{canonical_uri}\n{canonical_querystring}\n{canonical_headers}\n{signed_headers}\n{body_hash}"
    
    algorithm = 'AWS4-HMAC-SHA256'
    credential_scope = f"{date_stamp}/auto/s3/aws4_request"
    string_to_sign = f"{algorithm}\n{amz_date}\n{credential_scope}\n{hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()}"
    
    signing_key = get_signature_key(secret_key, date_stamp, 'auto', 's3')
    signature = hmac.new(signing_key, string_to_sign.encode('utf-8'), hashlib.sha256).hexdigest()
    
    authorization_header = f"{algorithm} Credential={access_key}/{credential_scope}, SignedHeaders={signed_headers}, Signature={signature}"
    
    headers = {
        'Host': host,
        'x-amz-date': amz_date,
        'x-amz-content-sha256': body_hash,
        'Authorization': authorization_header,
    }
    
    url = f"https://{host}{canonical_uri}"
    if query_params:
        url += "?" + urllib.parse.urlencode(query_params)
        
    req = urllib.request.Request(url, headers=headers, method=method)
    return req

def main():
    account_id = "66c40e0caaaa333ca0f4977bf32be2a7"
    access_key = "ccf641ce7fee6d2f1ec4c07a927f0b9c"
    secret_key = "abd1bc78a2c92791610e68cf4c0d253a56090740a67eec5462f667c91858eb34"
    bucket = "haispaceproject"
    host = f"{account_id}.r2.cloudflarestorage.com"
    
    print("--- Listing files in R2 bucket ---")
    query_params = {
        'prefix': 'haispace-logs/',
        'list-type': '2'
    }
    req = aws_sigv4_request('GET', host, bucket, '', access_key, secret_key, query_params=query_params)
    try:
        with urllib.request.urlopen(req) as response:
            xml_data = response.read().decode('utf-8')
            
            root = ET.fromstring(xml_data)
            ns = {'s3': 'http://s3.amazonaws.com/doc/2006-03-01/'}
            keys = []
            for contents in root.findall('.//s3:Contents', ns):
                key = contents.find('s3:Key', ns).text
                last_modified = contents.find('s3:LastModified', ns).text
                size = contents.find('s3:Size', ns).text
                keys.append((key, last_modified, size))
            
            keys.sort(key=lambda x: x[1], reverse=True)
            
            # Create a local directory if it doesn't exist
            os.makedirs("scratch/logs", exist_ok=True)
            
            # Let's download the top 15 latest files
            for k, lm, sz in keys[:15]:
                print(f"Key: {k} | Modified: {lm} | Size: {sz} bytes")
                local_name = k.replace("haispace-logs/", "").replace("/", "_")
                local_path = f"scratch/logs/{local_name}"
                
                req_get = aws_sigv4_request('GET', host, bucket, k, access_key, secret_key)
                try:
                    with urllib.request.urlopen(req_get) as resp_get:
                        content = resp_get.read().decode('utf-8')
                        with open(local_path, "w", encoding="utf-8") as f:
                            f.write(content)
                        print(f"  -> Saved to {local_path}")
                except Exception as e:
                    print(f"  -> Error downloading {k}: {e}")
                    
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
