const tabs = ['概览', '动态', 'Agent', '配额'];

export default function App() {
  return (
    <main>
      <header><h1>magpie</h1></header>
      <nav aria-label="主导航">
        {tabs.map((tab, index) => <button type="button" aria-current={index === 0 ? 'page' : undefined}>{tab}</button>)}
      </nav>
    </main>
  );
}
