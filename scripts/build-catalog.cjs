// Generate the explicit, reviewable field catalogue from the original SQL comments.
// Runtime code only consumes catalog.json; it never parses SQL comments.
const fs = require('fs');
const sql = fs.readFileSync('src/main/resources/db/migrations/V2__dictionary_tables.sql', 'utf8');
const blocks = [...sql.matchAll(/^-+ (\w+) -+ ([\d.]+)\r?\n([\s\S]*?)(?=^-+ |$(?![\s\S]))/gm)];
const result = [];
for (const block of blocks) {
  const [, name, oid, body] = block;
  const start = body.indexOf('(');
  const end = body.indexOf('\n);');
  const columns = [];
  const lines = body.slice(start + 1, end).split(/\r?\n/);
  let current;
  let keys = [];
  for (const line of lines) {
    const pk = line.match(/^\s*primary key \(([^)]+)\)/i);
    if (pk) keys = pk[1].split(',').map(s => s.trim());
    const c = line.match(/^\s+(\w+)\s+(bigint|integer|boolean|text|varchar\(\d+\)|char\(\d+\)|numeric\(\d+(?:,\s*\d+)?\)|timestamp without time zone)(.*)/i);
    if (c) {
      current = { target: c[1], type: c[2], source: null };
      columns.push(current);
      if (/primary key/i.test(c[3])) keys.push(c[1]);
    }
    const comment = line.match(/--\s*([A-Za-z][A-Za-z0-9_-]*)(?=:|\s*$)/);
    if (current && comment) current.source = comment[1];
  }
  const mapped = columns.filter(c => !['is_deleted', 'search_synonym'].includes(c.target)
    && !(c.target === 'display_order' && c.source === null));
  for (const c of mapped) {
    if (!c.source && c.target === 'valid_from' && name.startsWith('foms_')) c.source = 'DATEBEG';
    if (!c.source && c.target === 'personal_account_income_admin') c.source = c.target;
    if (!c.source) throw new Error(`Missing mapping ${name}.${c.target}`);
  }
  if (!keys.length) throw new Error(`Missing primary key ${name}`);
  result.push({name, oid, keys, columns: mapped});
}
if (result.length !== (sql.match(/create table if not exists/g) || []).length)
  throw new Error('Not all tables parsed');
result.push({name:'direction_type', oid:'1.2.643.5.1.13.13.11.1009', keys:['id'], columns:[
  {target:'id',type:'bigint',source:'ID'},
  {target:'name',type:'text',source:'NAME'},
  {target:'doc',type:'text',source:'DOC'},
  {target:'display_order',type:'numeric(10)',source:'SORT',staging:'sort'}
]});
fs.writeFileSync('src/main/resources/dictionary-catalog.json', JSON.stringify(result, null, 2) + '\n');
console.log(`Generated ${result.length} dictionary definitions`);
