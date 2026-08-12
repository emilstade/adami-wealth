import React, { useState } from 'react';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

let supabase = null;
if (SUPABASE_URL && SUPABASE_ANON_KEY) {
  supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}

export default function App() {
  const [view, setView] = useState('login');
  const [loading, setLoading] = useState(false);
  const [erro, setErro] = useState('');
  
  const [assessor, setAssessor] = useState(null);
  const [email, setEmail] = useState('pedro@adamiwealth.com');
  const [senha, setSenha] = useState('123456');
  
  const [clientes] = useState([
    { id: '1', nome: 'João Silva', cpf_cnpj: '123.456.789-00', pl: 1750000 },
    { id: '2', nome: 'Maria Santos', cpf_cnpj: '987.654.321-00', pl: 850000 },
    { id: '3', nome: 'Empresa XYZ', cpf_cnpj: '12.345.678/0001-90', pl: 2500000 }
  ]);
  
  const [clienteSelecionado, setClienteSelecionado] = useState(null);
  const [mesAtual, setMesAtual] = useState(2);
  const [anoAtual, setAnoAtual] = useState(2025);
  const [contas, setContas] = useState([
    { id: 1, nome: 'XP João', instituicao: 'XP', saldo: 1000000, aplicacoes: 10000, resgates: 0, rend_pct: 1.5, rend_reais: 15000 },
    { id: 2, nome: 'CDB Banco', instituicao: 'BB', saldo: 250000, aplicacoes: 0, resgates: 0, rend_pct: 0.8, rend_reais: 2000 },
    { id: 3, nome: 'Tesouro', instituicao: 'Tesouro', saldo: 500000, aplicacoes: 0, resgates: 0, rend_pct: 1.2, rend_reais: 6000 }
  ]);
  const [indicadores, setIndicadores] = useState({
    cdi: 1.22, ipca: 0.85, ibovespa: 2.1, sp500: 1.8,
    poupanca: 0.7, dolar: 0.5, ouro: 1.2, ifix: 0.9
  });
  
  const meses = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    setErro('');
    try {
      setAssessor({ id: '1', nome: 'Pedro Silva', email });
      setView('dashboard');
    } catch (e) {
      setErro('Erro: ' + e.message);
    } finally {
      setLoading(false);
    }
  };

  const handleSelecionarCliente = (cliente) => {
    setClienteSelecionado(cliente);
    setView('formulario');
  };

  const handleAtualizarConta = (idx, campo, valor) => {
    const novasContas = [...contas];
    novasContas[idx][campo] = isNaN(valor) ? valor : parseFloat(valor);
    setContas(novasContas);
  };

  const handleAdicionarConta = () => {
    setContas([...contas, {
      id: Date.now(),
      nome: '',
      instituicao: '',
      saldo: 0,
      aplicacoes: 0,
      resgates: 0,
      rend_pct: 0,
      rend_reais: 0
    }]);
  };

  const handleRemoverConta = (idx) => {
    setContas(contas.filter((_, i) => i !== idx));
  };

  const handleAtualizarIndicador = (campo, valor) => {
    setIndicadores({ ...indicadores, [campo]: parseFloat(valor) || 0 });
  };

  const handleSalvarDados = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      console.log('Salvando...', { clienteSelecionado, mesAtual, anoAtual, contas, indicadores });
      setView('relatorio');
    } catch (e) {
      setErro('Erro: ' + e.message);
    } finally {
      setLoading(false);
    }
  };

  if (view === 'login') {
    return <TelaLogin onLogin={handleLogin} email={email} setEmail={setEmail} senha={senha} setSenha={setSenha} loading={loading} erro={erro} />;
  }

  if (view === 'dashboard') {
    return <TelaDashboard assessor={assessor} clientes={clientes} onSelecionarCliente={handleSelecionarCliente} onLogout={() => { setAssessor(null); setView('login'); }} />;
  }

  if (view === 'formulario') {
    return (
      <TelaFormulario
        cliente={clienteSelecionado}
        mes={mesAtual}
        ano={anoAtual}
        setMes={setMesAtual}
        setAno={setAnoAtual}
        contas={contas}
        onAtualizarConta={handleAtualizarConta}
        onAdicionarConta={handleAdicionarConta}
        onRemoverConta={handleRemoverConta}
        indicadores={indicadores}
        onAtualizarIndicador={handleAtualizarIndicador}
        onSalvar={handleSalvarDados}
        onVoltar={() => setView('dashboard')}
        meses={meses}
        loading={loading}
      />
    );
  }

  if (view === 'relatorio') {
    return (
      <TelaRelatorio
        cliente={clienteSelecionado}
        mes={mesAtual}
        ano={anoAtual}
        contas={contas}
        indicadores={indicadores}
        onVoltar={() => setView('dashboard')}
        meses={meses}
      />
    );
  }
}

function TelaLogin({ onLogin, email, setEmail, senha, setSenha, loading, erro }) {
  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'linear-gradient(135deg, #1e3c72 0%, #2a5298 100%)', fontFamily: 'Arial, sans-serif' }}>
      <div style={{ background: 'white', padding: '40px', borderRadius: '12px', width: '100%', maxWidth: '400px', boxShadow: '0 10px 40px rgba(0,0,0,0.2)' }}>
        <h1 style={{ textAlign: 'center', marginBottom: '30px', color: '#1e3c72', fontSize: '32px' }}>🏛️ Adami Wealth</h1>
        
        {erro && <div style={{ background: '#fee', color: '#c33', padding: '12px', borderRadius: '6px', marginBottom: '15px', fontSize: '14px' }}>⚠️ {erro}</div>}
        
        <form onSubmit={onLogin}>
          <div style={{ marginBottom: '15px' }}>
            <label style={{ display: 'block', fontSize: '12px', color: '#666', fontWeight: 'bold', marginBottom: '5px' }}>EMAIL</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              style={{ width: '100%', padding: '12px', border: '1px solid #ddd', borderRadius: '6px', fontSize: '14px', boxSizing: 'border-box' }}
              placeholder="seu@email.com"
              required
            />
          </div>

          <div style={{ marginBottom: '20px' }}>
            <label style={{ display: 'block', fontSize: '12px', color: '#666', fontWeight: 'bold', marginBottom: '5px' }}>SENHA</label>
            <input
              type="password"
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              style={{ width: '100%', padding: '12px', border: '1px solid #ddd', borderRadius: '6px', fontSize: '14px', boxSizing: 'border-box' }}
              placeholder="••••••"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            style={{
              width: '100%',
              padding: '12px',
              background: '#1e3c72',
              color: 'white',
              border: 'none',
              borderRadius: '6px',
              fontWeight: 'bold',
              cursor: loading ? 'wait' : 'pointer',
              fontSize: '16px',
              opacity: loading ? 0.7 : 1
            }}
          >
            {loading ? '⏳ Entrando...' : '✓ Entrar'}
          </button>
        </form>

        <p style={{ textAlign: 'center', marginTop: '20px', fontSize: '12px', color: '#999' }}>
          Teste: pedro@adamiwealth.com / 123456
        </p>
      </div>
    </div>
  );
}

function TelaDashboard({ assessor, clientes, onSelecionarCliente, onLogout }) {
  return (
    <div style={{ minHeight: '100vh', background: '#f5f5f5', fontFamily: 'Arial, sans-serif' }}>
      <div style={{ background: '#1e3c72', color: 'white', padding: '20px' }}>
        <div style={{ maxWidth: '1200px', margin: '0 auto', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <h1 style={{ margin: '0 0 5px', fontSize: '24px' }}>🏛️ Adami Wealth</h1>
            <p style={{ margin: '0', opacity: 0.9 }}>Bem-vindo, {assessor.nome}!</p>
          </div>
          <button onClick={onLogout} style={{ padding: '8px 16px', background: 'rgba(255,255,255,0.2)', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>
            Sair
          </button>
        </div>
      </div>

      <div style={{ maxWidth: '1200px', margin: '0 auto', padding: '30px 20px' }}>
        <h2 style={{ color: '#1e3c72', marginBottom: '20px' }}>Meus Clientes ({clientes.length})</h2>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '20px' }}>
          {clientes.map(cliente => (
            <div key={cliente.id} style={{ background: 'white', padding: '20px', borderRadius: '8px', boxShadow: '0 2px 8px rgba(0,0,0,0.1)' }}>
              <h3 style={{ color: '#1e3c72', margin: '0 0 8px', fontSize: '18px' }}>{cliente.nome}</h3>
              <p style={{ fontSize: '12px', color: '#999', margin: '5px 0' }}>📋 {cliente.cpf_cnpj}</p>
              <p style={{ fontSize: '20px', color: '#2a5298', fontWeight: 'bold', margin: '10px 0' }}>R$ {(cliente.pl / 1000000).toFixed(2)}M</p>
              <button
                onClick={() => onSelecionarCliente(cliente)}
                style={{ width: '100%', padding: '10px', background: '#1e3c72', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}
              >
                📊 Atualizar Dados
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function TelaFormulario({ cliente, mes, ano, setMes, setAno, contas, onAtualizarConta, onAdicionarConta, onRemoverConta, indicadores, onAtualizarIndicador, onSalvar, onVoltar, meses, loading }) {
  return (
    <div style={{ minHeight: '100vh', background: '#f5f5f5', fontFamily: 'Arial, sans-serif' }}>
      <div style={{ background: '#1e3c72', color: 'white', padding: '20px' }}>
        <div style={{ maxWidth: '1200px', margin: '0 auto' }}>
          <button onClick={onVoltar} style={{ background: 'rgba(255,255,255,0.2)', color: 'white', border: 'none', padding: '8px 16px', borderRadius: '4px', cursor: 'pointer', marginBottom: '15px' }}>
            ← Voltar
          </button>
          <h1 style={{ margin: '0 0 5px', fontSize: '24px' }}>Atualizar - {cliente.nome}</h1>
          <p style={{ margin: '0', opacity: 0.9 }}>{meses[mes - 1]} de {ano}</p>
        </div>
      </div>

      <div style={{ maxWidth: '1200px', margin: '0 auto', padding: '30px 20px' }}>
        <form onSubmit={onSalvar}>
          <div style={{ background: 'white', padding: '20px', borderRadius: '8px', marginBottom: '20px', overflowX: 'auto' }}>
            <h3 style={{ marginTop: '0', color: '#1e3c72' }}>💼 Contas</h3>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '12px' }}>
              <thead>
                <tr style={{ borderBottom: '2px solid #1e3c72', background: '#f9f9f9' }}>
                  <th style={{ padding: '10px', textAlign: 'left', color: '#1e3c72', fontWeight: 'bold' }}>Conta</th>
                  <th style={{ padding: '10px', textAlign: 'left', color: '#1e3c72', fontWeight: 'bold' }}>Instituição</th>
                  <th style={{ padding: '10px', textAlign: 'right', color: '#1e3c72', fontWeight: 'bold' }}>Saldo</th>
                  <th style={{ padding: '10px', textAlign: 'right', color: '#1e3c72', fontWeight: 'bold' }}>Rend %</th>
                  <th style={{ padding: '10px', textAlign: 'right', color: '#1e3c72', fontWeight: 'bold' }}>Rend R$</th>
                  <th style={{ padding: '10px', textAlign: 'center', color: '#1e3c72', fontWeight: 'bold' }}>Ação</th>
                </tr>
              </thead>
              <tbody>
                {contas.map((conta, idx) => (
                  <tr key={conta.id} style={{ borderBottom: '1px solid #eee' }}>
                    <td style={{ padding: '10px' }}><input type="text" value={conta.nome} onChange={(e) => onAtualizarConta(idx, 'nome', e.target.value)} style={{ width: '100%', padding: '6px', border: '1px solid #ddd', borderRadius: '4px' }} /></td>
                    <td style={{ padding: '10px' }}><input type="text" value={conta.instituicao} onChange={(e) => onAtualizarConta(idx, 'instituicao', e.target.value)} style={{ width: '100%', padding: '6px', border: '1px solid #ddd', borderRadius: '4px' }} /></td>
                    <td style={{ padding: '10px' }}><input type="number" value={conta.saldo} onChange={(e) => onAtualizarConta(idx, 'saldo', e.target.value)} style={{ width: '100%', padding: '6px', border: '1px solid #ddd', borderRadius: '4px' }} /></td>
                    <td style={{ padding: '10px' }}><input type="number" step="0.01" value={conta.rend_pct} onChange={(e) => onAtualizarConta(idx, 'rend_pct', e.target.value)} style={{ width: '100%', padding: '6px', border: '1px solid #ddd', borderRadius: '4px' }} /></td>
                    <td style={{ padding: '10px' }}><input type="number" value={conta.rend_reais} onChange={(e) => onAtualizarConta(idx, 'rend_reais', e.target.value)} style={{ width: '100%', padding: '6px', border: '1px solid #ddd', borderRadius: '4px' }} /></td>
                    <td style={{ padding: '10px', textAlign: 'center' }}><button type="button" onClick={() => onRemoverConta(idx)} style={{ background: '#e33', color: 'white', border: 'none', padding: '6px 12px', borderRadius: '4px', cursor: 'pointer' }}>✕</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
            <button type="button" onClick={onAdicionarConta} style={{ marginTop: '15px', padding: '10px 20px', background: '#2a5298', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>
              + Adicionar Conta
            </button>
          </div>

          <div style={{ background: 'white', padding: '20px', borderRadius: '8px', marginBottom: '20px' }}>
            <h3 style={{ marginTop: '0', color: '#1e3c72' }}>📈 Indicadores do Mês</h3>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(120px, 1fr))', gap: '15px' }}>
              {[
                { label: 'CDI', campo: 'cdi' },
                { label: 'IPCA', campo: 'ipca' },
                { label: 'IBOVESPA', campo: 'ibovespa' },
                { label: 'S&P 500', campo: 'sp500' },
                { label: 'POUPANÇA', campo: 'poupanca' },
                { label: 'DÓLAR', campo: 'dolar' },
                { label: 'OURO', campo: 'ouro' },
                { label: 'IFIX', campo: 'ifix' }
              ].map(({ label, campo }) => (
                <div key={campo}>
                  <label style={{ display: 'block', fontSize: '11px', color: '#666', marginBottom: '5px', fontWeight: 'bold' }}>{label} (%)</label>
                  <input type="number" step="0.01" value={indicadores[campo]} onChange={(e) => onAtualizarIndicador(campo, e.target.value)} style={{ width: '100%', padding: '8px', border: '1px solid #ddd', borderRadius: '4px' }} />
                </div>
              ))}
            </div>
          </div>

          <div style={{ display: 'flex', gap: '15px' }}>
            <button type="submit" disabled={loading} style={{ padding: '12px 30px', background: '#1e3c72', color: 'white', border: 'none', borderRadius: '4px', cursor: loading ? 'wait' : 'pointer', fontWeight: 'bold', opacity: loading ? 0.7 : 1 }}>
              {loading ? '⏳ Salvando...' : '✓ Salvar e Gerar Relatório'}
            </button>
            <button type="button" onClick={onVoltar} style={{ padding: '12px 30px', background: '#999', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>
              Cancelar
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

function TelaRelatorio({ cliente, mes, ano, contas, indicadores, onVoltar, meses }) {
  const mesNome = meses[mes - 1];
  const plTotal = contas.reduce((sum, c) => sum + c.saldo, 0);
  const rendimentoTotal = contas.reduce((sum, c) => sum + c.rend_reais, 0);
  const rendimentoPct = plTotal > 0 ? (rendimentoTotal / plTotal) * 100 : 0;

  const porInstituicao = {};
  contas.forEach(conta => {
    if (!porInstituicao[conta.instituicao]) porInstituicao[conta.instituicao] = 0;
    porInstituicao[conta.instituicao] += conta.saldo;
  });
  const instituicoes = Object.entries(porInstituicao).map(([nome, valor]) => ({
    nome,
    valor,
    percentual: (valor / plTotal) * 100
  })).sort((a, b) => b.valor - a.valor);

  return (
    <div style={{ minHeight: '100vh', background: '#f5f5f5', fontFamily: 'Arial, sans-serif' }}>
      <div style={{ background: '#1e3c72', color: 'white', padding: '20px' }}>
        <div style={{ maxWidth: '1200px', margin: '0 auto' }}>
          <button onClick={onVoltar} style={{ background: 'rgba(255,255,255,0.2)', color: 'white', border: 'none', padding: '8px 16px', borderRadius: '4px', cursor: 'pointer', marginBottom: '15px' }}>
            ← Voltar
          </button>
          <h1 style={{ margin: '0 0 5px', fontSize: '24px' }}>📄 Relatório - {cliente.nome}</h1>
          <p style={{ margin: '0', opacity: 0.9 }}>{mesNome} de {ano}</p>
        </div>
      </div>

      <div style={{ maxWidth: '1200px', margin: '0 auto', padding: '30px 20px' }}>
        <div style={{ background: '#1e3c72', color: 'white', padding: '60px 40px', borderRadius: '8px', textAlign: 'center', marginBottom: '40px' }}>
          <p style={{ fontSize: '12px', textTransform: 'uppercase', letterSpacing: '2px', opacity: 0.8 }}>Relatório</p>
          <h1 style={{ fontSize: '40px', margin: '20px 0', fontWeight: 'bold' }}>Relatório Consolidado de Investimentos</h1>
          <p style={{ fontSize: '18px', margin: '20px 0', opacity: 0.9 }}>{cliente.nome}</p>
          <hr style={{ borderColor: 'rgba(255,255,255,0.3)', margin: '30px 0' }} />
          <p style={{ fontSize: '16px', margin: '30px 0', opacity: 0.9 }}>{mesNome} de {ano}</p>
          <p style={{ fontSize: '12px', opacity: 0.6, marginTop: '60px' }}>🏛️ ADAMI WEALTH</p>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '15px', marginBottom: '40px' }}>
          <div style={{ background: 'white', padding: '20px', borderRadius: '8px', textAlign: 'center', borderTop: '3px solid #1e3c72' }}>
            <p style={{ fontSize: '11px', color: '#999', fontWeight: 'bold', textTransform: 'uppercase', marginBottom: '10px' }}>Patrimônio</p>
            <p style={{ fontSize: '24px', fontWeight: 'bold', color: '#1e3c72', margin: '0' }}>R$ {(plTotal / 1000000).toFixed(2)}M</p>
          </div>
          <div style={{ background: 'white', padding: '20px', borderRadius: '8px', textAlign: 'center', borderTop: '3px solid #2a5298' }}>
            <p style={{ fontSize: '11px', color: '#999', fontWeight: 'bold', textTransform: 'uppercase', marginBottom: '10px' }}>Rentabilidade</p>
            <p style={{ fontSize: '24px', fontWeight: 'bold', color: '#2a5298', margin: '0' }}>{rendimentoPct.toFixed(2)}%</p>
          </div>
          <div style={{ background: 'white', padding: '20px', borderRadius: '8px', textAlign: 'center', borderTop: '3px solid #0a7344' }}>
            <p style={{ fontSize: '11px', color: '#999', fontWeight: 'bold', textTransform: 'uppercase', marginBottom: '10px' }}>Resultado</p>
            <p style={{ fontSize: '24px', fontWeight: 'bold', color: '#0a7344', margin: '0' }}>R$ {rendimentoTotal.toLocaleString('pt-BR')}</p>
          </div>
        </div>

        <div style={{ background: 'white', padding: '20px', borderRadius: '8px', marginBottom: '40px' }}>
          <h3 style={{ marginTop: '0', color: '#1e3c72' }}>📊 Distribuição por Instituição</h3>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <tbody>
              {instituicoes.map((inst) => (
                <tr key={inst.nome} style={{ borderBottom: '1px solid #eee' }}>
                  <td style={{ padding: '10px' }}>{inst.nome}</td>
                  <td style={{ padding: '10px', textAlign: 'right' }}>{inst.percentual.toFixed(1)}%</td>
                  <td style={{ padding: '10px', textAlign: 'right', fontWeight: 'bold', color: '#1e3c72' }}>R$ {inst.valor.toLocaleString('pt-BR')}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div style={{ display: 'flex', gap: '15px', marginBottom: '30px' }}>
          <button onClick={() => alert('📥 PDF - Em breve!')} style={{ padding: '12px 30px', background: '#1e3c72', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}>
            📥 Baixar PDF
          </button>
          <button onClick={onVoltar} style={{ padding: '12px 30px', background: '#999', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer' }}>
            Voltar
          </button>
        </div>
      </div>
    </div>
  );
}
