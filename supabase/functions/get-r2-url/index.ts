// get-r2-url — Cloudflare R2 Presigned URL 발급용 Supabase Edge Function.
//
// 목적: 게임 일러스트 등 자산을 공개 URL이 아니라 Cloudflare R2에 비공개로
// 두고, 클라이언트가 파일 경로(objectKey)만 넘기면 이 함수가 1시간짜리
// GET 전용 서명 URL(Presigned URL)을 발급해 준다. R2 접근 키는 여기(서버
// 쪽 Secrets)에만 있고 클라이언트 번들에는 절대 포함되지 않는다.
//
// 서명 라이브러리로 `@aws-sdk/client-s3` 대신 `aws4fetch`를 쓴다 —
// AWS SDK는 Node 지향이라 Deno Edge 런타임에서 무겁고(콜드 스타트 지연),
// aws4fetch는 SigV4 서명 하나만 목적으로 만들어진 의존성 없는 초경량
// 라이브러리라 Edge Function에 훨씬 적합하다. R2는 S3 호환 API를 제공하므로
// (region: "auto") 이 서명 방식이 그대로 통한다.
//
// 배포: `supabase functions deploy get-r2-url`
// 시크릿 등록(전부 필수):
//   supabase secrets set R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
//   supabase secrets set R2_ACCESS_KEY_ID=...
//   supabase secrets set R2_SECRET_ACCESS_KEY=...
//   supabase secrets set R2_BUCKET_NAME=...

import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20';

const corsHeaders = {
  // 웹 클라이언트(Flutter web build)가 다른 오리진에서 이 함수를 호출하므로
  // CORS를 열어야 한다 — 실제 배포 도메인이 고정되면 '*' 대신 그 도메인만
  // 허용하도록 좁히는 걸 권장한다.
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const jsonResponse = (body: unknown, status: number): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

/// 1시간 — 요구사항 그대로. 이 값이 곧 클라이언트(StorageManager)가
/// 캐시를 얼마나 신뢰할 수 있는지의 기준이므로, 여기서 바꾸면
/// StorageManager의 캐시 TTL도 반드시 함께 맞춰야 한다.
const PRESIGNED_URL_EXPIRES_IN_SECONDS = 3600;

/// `objectKey`가 R2 버킷 "밖"을 가리키게 만드는 값(상위 디렉터리 탈출,
/// 절대 경로, 다른 호스트로의 리다이렉트성 입력 등)을 걸러낸다 — 이
/// 함수는 인증 없이(또는 익명 인증만으로) 호출될 수 있으므로, objectKey를
/// 검증 없이 그대로 서명 대상 URL에 꽂으면 버킷 밖 자원을 서명해 주는
/// 통로가 될 수 있다.
function isValidObjectKey(key: string): boolean {
  if (key.length === 0 || key.length > 1024) {
    return false;
  }
  if (key.includes('..') || key.startsWith('/') || key.includes('://')) {
    return false;
  }
  return true;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    // 브라우저의 CORS preflight 요청 — 본문 없이 허용 헤더만 돌려준다.
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed. Use POST.' }, 405);
  }

  let objectKey: unknown;
  try {
    const body = await req.json();
    objectKey = body?.objectKey;
  } catch {
    return jsonResponse({ error: 'Request body must be valid JSON.' }, 400);
  }

  if (typeof objectKey !== 'string' || !isValidObjectKey(objectKey)) {
    return jsonResponse(
      { error: 'objectKey must be a non-empty relative path string.' },
      400,
    );
  }

  const endpoint = Deno.env.get('R2_ENDPOINT');
  const accessKeyId = Deno.env.get('R2_ACCESS_KEY_ID');
  const secretAccessKey = Deno.env.get('R2_SECRET_ACCESS_KEY');
  const bucketName = Deno.env.get('R2_BUCKET_NAME');

  if (!endpoint || !accessKeyId || !secretAccessKey || !bucketName) {
    // 클라이언트에는 어떤 시크릿이 비어 있는지 노출하지 않는다 — 서버
    // 로그(Supabase 대시보드의 Edge Function 로그)에서만 원인을 확인한다.
    console.error(
      'get-r2-url: missing one or more required secrets ' +
        '(R2_ENDPOINT/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY/R2_BUCKET_NAME).',
    );
    return jsonResponse({ error: 'Server is not configured.' }, 500);
  }

  // [주의: 실측으로 발견된 실패 사례] `R2_ENDPOINT` 시크릿을 `supabase
  // secrets set`으로 등록할 때 오타(예: 복사 과정에서 "https://" 앞에
  // 글자가 하나 더 붙어 "hhttps://..."가 되는 경우)가 나면, 이 함수는
  // 여전히 200과 함께 "그럴듯해 보이는" JSON을 돌려준다 — 서명 자체는
  // 문자열이 뭐가 됐든 성공하기 때문이다. 하지만 그 URL의 스킴이
  // 깨져 있어서 클라이언트가 실제로 요청을 보내는 단계에서 전부
  // 조용히(또는 이해하기 어려운 에러로) 실패한다. "발급은 됐는데 이미지가
  // 하나도 안 뜬다"는 훨씬 진단하기 어려운 증상으로 나타나므로, 여기서
  // 미리 걸러 명확한 에러로 실패시킨다.
  if (!/^https?:\/\//i.test(endpoint)) {
    console.error(
      `get-r2-url: R2_ENDPOINT secret looks malformed (does not start with ` +
        `http:// or https://): "${endpoint}". Re-check for typos, e.g. ` +
        `an accidental extra character before "https://".`,
    );
    return jsonResponse({ error: 'Server is not configured correctly.' }, 500);
  }

  try {
    const client = new AwsClient({
      accessKeyId,
      secretAccessKey,
      service: 's3',
      // R2는 리전 개념이 없다 — S3 호환 API가 "auto"를 그대로 받아들인다.
      region: 'auto',
    });

    const objectUrl = new URL(
      `${endpoint.replace(/\/+$/, '')}/${bucketName}/${objectKey}`,
    );
    objectUrl.searchParams.set(
      'X-Amz-Expires',
      String(PRESIGNED_URL_EXPIRES_IN_SECONDS),
    );

    // signQuery: true → 서명이 헤더가 아니라 쿼리스트링에 실린다. 그래야
    // 클라이언트가 이 URL을 평범한 GET 링크(Image.network 등)로 그대로
    // 쓸 수 있다 — 별도 Authorization 헤더를 붙여줄 필요가 없다.
    const signedRequest = await client.sign(
      new Request(objectUrl, { method: 'GET' }),
      { aws: { signQuery: true } },
    );

    return jsonResponse(
      {
        url: signedRequest.url,
        expiresIn: PRESIGNED_URL_EXPIRES_IN_SECONDS,
      },
      200,
    );
  } catch (error) {
    console.error('get-r2-url: failed to sign URL:', error);
    return jsonResponse({ error: 'Failed to generate URL.' }, 500);
  }
});
