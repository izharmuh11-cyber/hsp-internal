import urllib.request
import json
import sys

def main():
    req = urllib.request.Request('https://api.github.com/repos/izharmuh11-cyber/hsp-internal/actions/runs', headers={'User-Agent': 'Mozilla/5.0'})
    res = urllib.request.urlopen(req)
    data = json.loads(res.read())
    run = data['workflow_runs'][0]
    print(f"Run ID: {run['id']}")
    print(f"Title: {run['display_title']}")
    print(f"Status: {run['status']}")
    print(f"Conclusion: {run['conclusion']}")
    
    jobs_url = run['jobs_url']
    req_jobs = urllib.request.Request(jobs_url, headers={'User-Agent': 'Mozilla/5.0'})
    res_jobs = urllib.request.urlopen(req_jobs)
    data_jobs = json.loads(res_jobs.read())
    
    for job in data_jobs['jobs']:
        print(f"\n==================================================")
        print(f"Job: {job['name']} - Status: {job['status']} - Conclusion: {job['conclusion']}")
        print(f"==================================================")
        
        job_id = job['id']
        # Try fetching logs
        logs_url = f"https://api.github.com/repos/izharmuh11-cyber/hsp-internal/actions/jobs/{job_id}/logs"
        req_logs = urllib.request.Request(logs_url, headers={'User-Agent': 'Mozilla/5.0'})
        try:
            res_logs = urllib.request.urlopen(req_logs)
            log_data = res_logs.read().decode('utf-8', errors='ignore')
            lines = log_data.split('\n')
            
            # Print compilation errors or warnings
            print("Errors/Warnings in log:")
            error_count = 0
            for line in lines:
                if 'error:' in line or 'warning:' in line or 'note:' in line or 'failed' in line.lower() or 'duplicate' in line:
                    # Clean timestamp from start of line if present (e.g. 2026-07-12T...)
                    clean_line = line
                    if len(line) > 28 and line[4] == '-' and line[7] == '-' and line[10] == 'T':
                        clean_line = line[29:]
                    print(clean_line)
                    error_count += 1
                    if error_count > 50:
                        print("... (truncated further errors) ...")
                        break
            if error_count == 0:
                # If no errors/warnings found, print the last 20 lines of the log
                print("Last 20 lines of log:")
                for line in lines[-20:]:
                    print(line)
        except Exception as e:
            print(f"Error fetching logs: {e}")

if __name__ == '__main__':
    main()
