// Viewer-request CloudFront Function.
//
// Rewrites URIs that look like directories so a private S3 origin (OAC) can
// serve the corresponding index.html:
//   /donate           -> /donate/index.html
//   /donate/          -> /donate/index.html
//   /legal/privacy    -> /legal/privacy/index.html
//   /_astro/a.b.js    -> unchanged (last segment has a "." — treated as file)
//   /                 -> unchanged (default_root_object handles the root)
//
// Runs on every viewer request at the edge. CloudFront Functions are billed
// per million invocations (~$0.10/M) with a 1 ms CPU budget; this is a
// handful of string ops and stays well under.
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    if (uri === '/' || uri === '') {
        return request;
    }

    if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
        return request;
    }

    var lastSegment = uri.substring(uri.lastIndexOf('/') + 1);
    if (lastSegment.indexOf('.') === -1) {
        request.uri = uri + '/index.html';
    }

    return request;
}
