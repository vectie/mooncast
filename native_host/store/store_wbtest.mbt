///|
async test "atomic store reuses an existing durable root across writes" {
  let root = "/tmp/mooncast-atomic-store-" + @async.now().to_string()
  let store = AtomicStore::new(root)
  let first = store.put_blob("first.bin", b"first")
  let second = store.put_blob("second.bin", b"second")
  assert_eq(first.key, "first.bin")
  assert_eq(second.key, "second.bin")
  assert_eq(store.get_blob("first.bin").unwrap().bytes, b"first")
  assert_eq(store.get_blob("second.bin").unwrap().bytes, b"second")
}
