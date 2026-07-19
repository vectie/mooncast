///|
pub(all) struct CommandSpec {
  executable : String
  arguments : Array[String]
  working_directory : String?
  timeout_ms : Int
  max_output_bytes : Int
} derive(Debug)

///|
pub(all) struct CommandResult {
  exit_code : Int?
  stdout : Bytes
  stderr : Bytes
  timed_out : Bool
  output_truncated : Bool
} derive(Debug)

///|
pub suberror CommandError {
  InvalidExecutable
  InvalidArgument(Int)
  InvalidLimit
} derive(Debug)

///|
fn validate(spec : CommandSpec) -> Unit raise CommandError {
  guard !spec.executable.is_empty() && !spec.executable.contains("\u0000") else {
    raise InvalidExecutable
  }
  for index, argument in spec.arguments {
    if argument.contains("\u0000") {
      raise InvalidArgument(index)
    }
  }
  guard spec.timeout_ms > 0 && spec.max_output_bytes > 0 else {
    raise InvalidLimit
  }
}

///|
async fn[R : @io.Reader] read_bounded(reader : R, limit : Int) -> (Bytes, Bool) {
  let output : Array[Byte] = []
  let mut truncated = false
  for ;; {
    let remaining = limit - output.length()
    if remaining <= 0 {
      match reader.read_some(max_len=65536) {
        None => break
        Some(_) => {
          truncated = true
          continue
        }
      }
    }
    match
      reader.read_some(
        max_len=if remaining < 65536 { remaining } else { 65536 },
      ) {
      None => break
      Some(chunk) =>
        for byte in chunk {
          output.push(byte)
        }
    }
  }
  (Bytes::from_array(output), truncated)
}

///|
/// Spawn an argv-only process. No shell is involved. Cancellation or timeout
/// propagates to the pinned async process package's hard cancellation handler.
pub async fn run_capture(spec : CommandSpec) -> CommandResult {
  validate(spec)
  let completed = @async.with_timeout_opt(spec.timeout_ms, () => {
    @async.with_task_group(group => {
      let (stdout_reader, stdout_writer) = @os_process.read_from_process()
      let (stderr_reader, stderr_writer) = @os_process.read_from_process()
      defer stdout_reader.close()
      defer stderr_reader.close()
      let cwd : StringView? = match spec.working_directory {
        Some(value) => Some(value[:])
        None => None
      }
      let process = @os_process.spawn(
        group,
        spec.executable,
        spec.arguments,
        stdout=stdout_writer,
        stderr=stderr_writer,
        cwd?,
        cancel_handler=@os_process.hard_cancel(),
      )
      let stdout_task = group.spawn(() => {
        read_bounded(stdout_reader, spec.max_output_bytes)
      })
      let stderr_task = group.spawn(() => {
        read_bounded(stderr_reader, spec.max_output_bytes)
      })
      let exit_code = process.wait()
      let (stdout, stdout_truncated) = stdout_task.wait()
      let (stderr, stderr_truncated) = stderr_task.wait()
      (exit_code, stdout, stderr, stdout_truncated || stderr_truncated)
    })
  })
  match completed {
    None =>
      {
        exit_code: None,
        stdout: b"",
        stderr: b"",
        timed_out: true,
        output_truncated: false,
      }
    Some((exit_code, stdout, stderr, output_truncated)) =>
      {
        exit_code: Some(exit_code),
        stdout,
        stderr,
        timed_out: false,
        output_truncated,
      }
  }
}
