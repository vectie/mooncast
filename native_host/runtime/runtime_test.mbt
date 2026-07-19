///|
test "secret refs accept only explicit environment names" {
  assert_true(SecretRef::from_env("MOONCAST_API_KEY") is Some(_))
  assert_true(SecretRef::from_env("api-key") is None)
  assert_true(SecretRef::from_env("1SECRET") is None)
}
