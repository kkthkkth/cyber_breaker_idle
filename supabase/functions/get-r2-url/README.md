# get-r2-url

Cloudflare R2에 비공개로 보관한 게임 에셋의 1시간짜리 GET Presigned URL을
발급하는 Supabase Edge Function. 클라이언트는 `objectKey`(R2 안의 상대
경로)만 보내고, R2 접근 키는 이 함수의 Secrets에만 존재한다 — 클라이언트
번들에는 절대 포함되지 않는다.

## 배포 전 준비물

1. Cloudflare R2 버킷과, 그 버킷에 대한 읽기 권한을 가진 R2 API 토큰
   (Access Key ID / Secret Access Key).
2. 게임 에셋이 실제로 그 버킷에 업로드되어 있어야 한다 — 이 함수는 URL만
   서명해 줄 뿐, 파일 자체를 옮겨주지 않는다.
3. [Supabase CLI](https://supabase.com/docs/guides/cli)가 설치되어 있고
   이 프로젝트에 로그인/링크되어 있어야 한다.

## 1. Secrets 등록

```bash
supabase secrets set R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
supabase secrets set R2_ACCESS_KEY_ID=<access-key-id>
supabase secrets set R2_SECRET_ACCESS_KEY=<secret-access-key>
supabase secrets set R2_BUCKET_NAME=<bucket-name>
```

네 개 모두 필수다 — 하나라도 비어 있으면 함수가 500과 함께
`"Server is not configured."`를 반환한다(실제 원인은 클라이언트에 노출하지
않고 Edge Function 로그에만 남긴다).

## 2. 배포

```bash
supabase functions deploy get-r2-url
```

## 3. 동작 확인

```bash
curl -X POST 'https://<project-ref>.functions.supabase.co/get-r2-url' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <anon-or-user-jwt>' \
  -d '{"objectKey": "characters/n1/n1_run1.png"}'
```

정상이면 `{"url": "https://...", "expiresIn": 3600}`이 온다.

## 클라이언트 연결

Flutter 쪽은 [lib/managers/storage_manager.dart](../../../lib/managers/storage_manager.dart)의
`StorageManager.instance.imageUrl(objectKey)`가 이 함수를 호출하고 결과를
캐싱한다. 다만 이 매니저는 아직 기존 `CustomSafeImage`/`RemoteSpriteLoader`
호출부에 연결돼 있지 않다 — R2에 에셋이 실제로 올라가고 이 함수가 배포된
뒤, 그 호출부들을 `StorageManager`를 쓰도록 바꾸는 리팩토링이 별도로
필요하다(지금 미리 바꿔 버리면 인프라가 준비되기 전까지 게임 이미지가
전부 깨진다).
