///|
struct Route {
  request_method : Method
  path : String
  handler : (Request) -> Response
}

///|
/// A small deterministic exact-route table. Domain packs register handlers;
/// the native host remains unaware of domain types.
pub struct Router {
  routes : Array[Route]
}

///|
pub fn Router::new() -> Router {
  { routes: [] }
}

///|
pub fn Router::add(
  self : Router,
  request_method : Method,
  path : String,
  handler : (Request) -> Response,
) -> Unit {
  self.routes.push({ request_method, path, handler })
}

///|
pub fn Router::dispatch(self : Router, request : Request) -> Response {
  for route in self.routes {
    if route.request_method == request.request_method &&
      route.path == request.path {
      return (route.handler)(request)
    }
  }
  not_found()
}
