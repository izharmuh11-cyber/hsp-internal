import urllib.request
import json

def main():
    req = urllib.request.Request(
        'https://api.github.com/repos/izharmuh11-cyber/hsp-internal/commits/main/check-runs',
        headers={'User-Agent': 'Mozilla/5.0', 'Accept': 'application/vnd.github.v3+json'}
    )
    try:
        res = urllib.request.urlopen(req)
        data = json.loads(res.read())
        print(f"Total check runs: {data['total_count']}")
        for check_run in data.get('check_runs', []):
            print(f"\n==========================================")
            print(f"Check Run: {check_run['name']}")
            print(f"Status: {check_run['status']} - Conclusion: {check_run['conclusion']}")
            output = check_run.get('output', {})
            if output:
                print(f"Title: {output.get('title')}")
                print(f"Summary: {output.get('summary')}")
            # Fetch annotations
            annotations_url = check_run.get('output', {}).get('annotations_url')
            if annotations_url:
                req_ann = urllib.request.Request(annotations_url, headers={'User-Agent': 'Mozilla/5.0'})
                ann_res = urllib.request.urlopen(req_ann)
                annotations = json.loads(ann_res.read())
                if annotations:
                    print("Annotations:")
                    for ann in annotations:
                        print(f"  [{ann['annotation_level'].upper()}] {ann['path']}:{ann['start_line']} - {ann['message']}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    main()
