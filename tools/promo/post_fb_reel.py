"""Publish a vertical video as a Reel on the Wick's Mods Facebook Page.

    python post_fb_reel.py <video.mp4> <caption.txt> [--dry-run]

Uses fb_page_id / fb_page_token from Wicksmodsinfo.txt (the N8N publisher
Page token, never printed). Reels upload in three steps: start a session,
send the bytes to rupload.facebook.com, then finish with the description.
"""
import os, re, sys, requests

GRAPH = 'https://graph.facebook.com/v21.0'


def creds():
    lines = open(os.path.expanduser('~/OneDrive/Documents/Wicksmodsinfo.txt'), encoding='utf-8-sig').read().splitlines()
    def val(key):
        for l in lines:
            m = re.match(r'\s*' + key + r'\s*[:=]\s*(\S+)', l)
            if m:
                return m.group(1)
        raise SystemExit(f'{key} missing from Wicksmodsinfo.txt')
    return val('fb_page_id'), val('fb_page_token')


def main():
    args = [a for a in sys.argv[1:] if a != '--dry-run']
    dry = '--dry-run' in sys.argv
    video, caption = args[0], open(args[1], encoding='utf-8').read().strip()
    page, token = creds()
    size = os.path.getsize(video)
    print(f'{os.path.basename(video)}: {size / 1e6:.1f} MB, caption {len(caption)} chars')
    if dry:
        print('--- caption ---\n' + caption + '\n--- dry run: nothing sent')
        return
    start = requests.post(f'{GRAPH}/{page}/video_reels', data={'upload_phase': 'start', 'access_token': token}).json()
    if 'video_id' not in start:
        raise SystemExit(f'start failed: {start.get("error", start)}')
    vid = start['video_id']
    with open(video, 'rb') as f:
        up = requests.post(start['upload_url'], data=f, headers={
            'Authorization': f'OAuth {token}', 'offset': '0', 'file_size': str(size)}).json()
    if not up.get('success'):
        raise SystemExit(f'upload failed: {up}')
    fin = requests.post(f'{GRAPH}/{page}/video_reels', data={
        'upload_phase': 'finish', 'video_id': vid, 'video_state': 'PUBLISHED',
        'description': caption, 'access_token': token}).json()
    if not fin.get('success'):
        raise SystemExit(f'finish failed: {fin.get("error", fin)}')
    print(f'published reel, video id {vid}')


if __name__ == '__main__':
    main()
