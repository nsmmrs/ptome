// Loaded into Node.js before each test program (dart_test.yaml): the
// program's socket to the test runner sends at once. Node waits by default
// (Nagle's algorithm) to send a small write while one before it is
// unacknowledged, and the runner acknowledges late (delayed ACK), so each
// test's last message waited ~40 ms: most of the Node suites' time.
const net = require('net');
const connect = net.connect;
net.connect = net.createConnection = function (...args) {
  const socket = connect.apply(this, args);
  socket.setNoDelay(true);
  return socket;
};
