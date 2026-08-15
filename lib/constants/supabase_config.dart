/// Supabase 프로젝트 접속 정보 — [SupabaseManager]/main.dart의
/// `Supabase.initialize`가 참조하는 단일 소스.
///
/// [anonKey]는 이름과 달리 "비밀 키"가 아니다 — 클라이언트 앱에 그대로
/// 박아 넣도록 설계된 공개(publishable) 키이고, 실제 접근 제어는 Supabase
/// 프로젝트의 Row Level Security(RLS) 정책이 담당한다. 여기에 넣으면 안 되는
/// 건 절대 클라이언트에 노출되면 안 되는 `service_role` 키뿐이다.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = 'https://chdscgqpjedrxqwraocj.supabase.co';
  static const String anonKey = 'sb_publishable_rN74lxAb1dKf3ETa3PWDOw_3vBI0oqq';
}
