import subprocess
import urllib.request
import json
import os
import re

class AuthRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new_req = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new_req:
            # If the redirect is to a different host (like S3/Azure), remove Auth header
            if 'github.com' not in new_req.host:
                if 'Authorization' in new_req.headers:
                    del new_req.headers['Authorization']
        return new_req

def get_git_credentials():
    p = subprocess.Popen(
        ['git', 'credential', 'fill'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    input_data = "protocol=https\nhost=github.com\n\n"
    stdout, stderr = p.communicate(input=input_data)
    
    username = None
    password = None
    for line in stdout.split('\n'):
        if line.startswith('username='):
            username = line.split('=', 1)[1].strip()
        elif line.startswith('password='):
            password = line.split('=', 1)[1].strip()
            
    return username, password

def main():
    username, token = get_git_credentials()
    if not token:
        print("Error: Could not retrieve GitHub token from Credential Manager.")
        return
        
    print(f"Retrieved token for user: {username}")
    
    # Install the custom redirect handler
    opener = urllib.request.build_opener(AuthRedirectHandler)
    urllib.request.install_opener(opener)
    
    # 1. Fetch latest run
    req = urllib.request.Request(
        'https://api.github.com/repos/izharmuh11-cyber/hsp-internal/actions/runs',
        headers={'User-Agent': 'Mozilla/5.0', 'Authorization': f'token {token}'}
    )
    res = urllib.request.urlopen(req)
    data = json.loads(res.read())
    run = data['workflow_runs'][0]
    print(f"Latest Run ID: {run['id']} ({run['display_title']}) - {run['status']} - {run['conclusion']}")
    
    # 2. Fetch jobs
    jobs_url = run['jobs_url']
    req_jobs = urllib.request.Request(
        jobs_url,
        headers={'User-Agent': 'Mozilla/5.0', 'Authorization': f'token {token}'}
    )
    res_jobs = urllib.request.urlopen(req_jobs)
    data_jobs = json.loads(res_jobs.read())
    
    for job in data_jobs['jobs']:
        print(f"\n==================================================")
        print(f"Job: {job['name']} - Status: {job['status']} - Conclusion: {job['conclusion']}")
        print(f"==================================================")
        
        job_id = job['id']
        logs_url = f"https://api.github.com/repos/izharmuh11-cyber/hsp-internal/actions/jobs/{job_id}/logs"
        req_logs = urllib.request.Request(
            logs_url,
            headers={'User-Agent': 'Mozilla/5.0', 'Authorization': f'token {token}'}
        )
        try:
            res_logs = urllib.request.urlopen(req_logs)
            log_data = res_logs.read().decode('utf-8', errors='ignore')
            lines = log_data.split('\n')
            
            # Print compilation errors or warnings
            print("Errors/Warnings in log:")
            error_count = 0
            for line in lines:
                if 'error:' in line or 'warning:' in line or 'note:' in line or 'failed' in line.lower() or 'duplicate' in line:
                    clean_line = line
                    if len(line) > 28 and line[4] == '-' and line[7] == '-' and line[10] == 'T':
                        clean_line = line[29:]
                    print(clean_line)
                    error_count += 1
                    if error_count > 50:
                        print("... (truncated further errors) ...")
                        break
            if error_count == 0:
                print("Last 20 lines of log:")
                for line in lines[-20:]:
                    print(line)
        except Exception as e:
            print(f"Error fetching logs for job {job_id}: {e}")

if __name__ == '__main__':
    main()
