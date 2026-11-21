// Bootstrap MySQL InnoDB Cluster once; three voters provide a majority for elections.
var rootPassword = os.getenv('MYSQL_ROOT_PASSWORD');
var appPassword = os.getenv('MYSQL_APP_PASSWORD');
if (!rootPassword || !appPassword) throw new Error('Required passwords are missing from environment');
function uri(host) { return 'root:' + rootPassword + '@' + host + ':3306'; }
function connect(host) { return mysql.getSession(uri(host)); }
['mysql1', 'mysql2', 'mysql3'].forEach(function(host) { print('Configuring ' + host); dba.configureInstance(uri(host), {restart: false}); });
function findPrimary() {
  for (var i = 1; i <= 3; i++) {
    var host = 'mysql' + i;
    var session = connect(host);
    var readOnly = session.runSql('SELECT @@global.read_only').fetchOne()[0];
    session.close();
    if (Number(readOnly) === 0) return host;
  }
  return null;
}
var primary = findPrimary();
var cluster;
function metadataExists() {
  var session = connect('mysql1');
  var found = Number(session.runSql("SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='mysql_innodb_cluster_metadata'").fetchOne()[0]) > 0;
  session.close();
  return found;
}
function mostUpToDateMember() {
  var sets = {};
  ['mysql1', 'mysql2', 'mysql3'].forEach(function(host) {
    var session = connect(host);
    sets[host] = session.runSql('SELECT @@GLOBAL.GTID_EXECUTED').fetchOne()[0];
    session.close();
  });
  var candidates = Object.keys(sets).filter(function(candidate) {
    return Object.keys(sets).every(function(member) {
      var session = connect(candidate);
      var subset = Number(session.runSql('SELECT GTID_SUBSET(?, ?)', [sets[member], sets[candidate]]).fetchOne()[0]);
      session.close();
      return subset === 1;
    });
  });
  if (candidates.length === 0) throw new Error('No MySQL member contains the complete GTID set; refusing unsafe cluster recovery');
  return candidates[0];
}
if (primary) {
  shell.connect(uri(primary));
  try { cluster = dba.getCluster('haCluster'); }
  catch (e) {
    if (metadataExists()) throw e;
    cluster = dba.createCluster('haCluster', {communicationStack: 'MYSQL', localAddress: primary + ':3306', consistency: 'BEFORE_ON_PRIMARY_FAILOVER'});
  }
} else {
  if (!metadataExists()) throw new Error('No writable MySQL primary is available for initial cluster creation');
  primary = mostUpToDateMember();
  print('Complete outage detected; recovering from GTID superset member ' + primary);
  shell.connect(uri(primary));
  cluster = dba.rebootClusterFromCompleteOutage('haCluster');
}
var status = cluster.status({extended: 1});
['mysql2', 'mysql3'].forEach(function(host) {
  if (!status.defaultReplicaSet || !Object.keys(status.defaultReplicaSet.topology || {}).some(function(key) { return key.indexOf(host) >= 0; })) {
    print('Joining ' + host);
    cluster.addInstance(uri(host), {recoveryMethod: 'clone'});
  }
});
primary = findPrimary();
var s = connect(primary);
s.runSql("CREATE DATABASE IF NOT EXISTS ha_lab");
s.runSql("CREATE USER IF NOT EXISTS 'ha_app'@'%' IDENTIFIED BY '" + appPassword + "'");
s.runSql("GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX ON ha_lab.* TO 'ha_app'@'%'");
print('InnoDB Cluster initialized; verify quorum and primary role before experiments.');
s.close();
