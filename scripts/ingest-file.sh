#!/bin/bash
# Usage: ./scripts/ingest-file.sh <filename>
# Example: ./scripts/ingest-file.sh my-doc.md
set -e

FILENAME="$1"
WIKI_ROOT="/Users/theo/workspace_tokamak/trh-wiki"

if [[ -z "$FILENAME" ]]; then
  echo "Usage: $0 <filename>"
  exit 1
fi

if [[ ! -f "$WIKI_ROOT/raw/inbox/$FILENAME" ]]; then
  echo "File not found: raw/inbox/$FILENAME"
  exit 1
fi

echo "[ingest] Starting: $FILENAME"
cd "$WIKI_ROOT"

PROMPT="raw/inbox/${FILENAME}에 새 파일이 추가됨. CLAUDE.md의 ingest 규칙에 따라 ingest를 실행해라.

파일: raw/inbox/${FILENAME}

ingest 필터 (반드시 지킬 것):
- forge 명령어, 파라미터 목록, 컨트랙트 주소 → wiki에 포함 금지 (소스에서 읽을 수 있음)
- non-obvious 인사이트만 기존 페이지에 추가: 설계 이유(why), 알아야 할 제약, cross-source 교차 인사이트
- 새 페이지: 기존 페이지 어디에도 맞지 않는 카테고리인 경우만 생성 (raw reformat 페이지 금지)
- wiki/log.md에 ingest 로그 추가
- git add, commit (메시지: 'wiki: ingest ${FILENAME}'), push 실행"

claude --dangerously-skip-permissions --print "$PROMPT"

echo "[ingest] Done: $FILENAME"
