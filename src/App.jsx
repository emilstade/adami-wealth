import React, { useState } from 'react';

export default function App() {
  const [view, setView] = useState('login');
  const [email, setEmail] = useState('pedro@adamiwealth.com');
  const [senha, setSenha] = useState('123456');
  const [assessor, setAssessor] = useState(null);

  const handleLogin = (e) => {
    e.preventDefault();
    setAssessor({ nome: 'Pedro Silva' });
    setView('dashboard');
  };

  if (view === 'login') {
    return (
      <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'linear-gradient(135deg, #1e3c72 0%, #2a5298 100%)' }}>
        <div style={{ background: 'white', padding: '40px', borderRadius: '12px', width: '100%', maxWidth: '400px' }}>
          <h1 style={{ textAlign: 'center', color: '#1e3c72', marginBottom: '30px' }}>🏛️ Adami Wealth</h1>
          <form onSubmit={handleLogin}>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} style={{ width: '100%', padding: '12px', marginBottom: '15px', border: '1px solid #ddd', borderRadius: '6px' }} required />
            <input type="password" value={senha} onChange={(e) => setSenha(e.target.value)} style={{ width: '100%', padding: '12px', marginBottom: '20px', border: '1px solid #ddd', borderRadius: '6px' }} required />
            <button type="submit" style={{ width: '100%', padding: '12px', background: '#1e3c72', color: 'white', border: 'none', borderRadius: '6px', fontWeight: 'bold', cursor: 'pointer' }}>Entrar</button>
          </form>
          <p style={{ textAlign: 'center', marginTop: '20px', fontSize: '12px', color: '#999' }}>
            Teste: pedro@adamiwealth.com / 123456
          </p>
        </div>
      </div>
    );
  }

  if (view === 'dashboard') {
    return (
      <div style={{ minHeight: '100vh', background: '#f5f5f5' }}>
        <div style={{ background: '#1e3c72', color: 'white', padding: '20px' }}>
          <div style={{ maxWidth: '1200px', margin: '0 auto' }}>
            <h1>🏛️ Adami Wealth</h1>
            <p>Bem-vindo, {assessor.nome}!</p>
            <button onClick={() => { setAssessor(null); setView('login'); }} style={{ marginTop: '10px', padding: '8px 16px', background: 'rgba(255,255,255,0.2)', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>Sair</button>
          </div>
        </div>
        <div style={{ maxWidth: '1200px', margin: '0 auto', padding: '30px 20px' }}>
          <h2 style={{ color: '#1e3c72', marginBottom: '20px' }}>✅ APP FUNCIONANDO!</h2>
          <div style={{ background: 'white', padding: '40px', borderRadius: '8px', textAlign: 'center' }}>
            <h1 style={{ fontSize: '48px', margin: '0 0 20px' }}>🎉</h1>
            <p style={{ fontSize: '24px', color: '#1e3c72', margin: '0 0 20px' }}>Sua app está ONLINE!</p>
            <p style={{ fontSize: '16px', color: '#666' }}>Em breve: Dashboard com clientes, formulários e relatórios.</p>
          </div>
        </div>
      </div>
    );
  }
}
