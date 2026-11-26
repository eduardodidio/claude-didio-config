import { Navigate, Routes, Route } from 'react-router-dom';
import { MainLayout } from '@/components/MainLayout';
import { Overview } from '@/views/Overview';
import { Features } from '@/views/Features';
import { Agents } from '@/views/Agents';
import EasterEggs from '@/views/EasterEggs';
import { MetaAgents } from '@/views/MetaAgents';
import { KanbanBoard } from '@/views/KanbanBoard';
import { Governance } from '@/views/Governance';
import { WarRoom } from '@/views/WarRoom';

export default function App() {
  return (
    <Routes>
      <Route element={<MainLayout />}>
        <Route index element={<Overview />} />
        <Route path="kanban" element={<KanbanBoard />} />
        <Route path="warroom" element={<WarRoom />} />
        <Route path="governance" element={<Governance />} />
        <Route path="features" element={<Features />} />
        <Route path="agents" element={<Agents />} />
        <Route path="meta-agents" element={<MetaAgents />} />
        <Route path="phrases" element={<EasterEggs />} />
        <Route path="easter-eggs" element={<Navigate to="/phrases" replace />} />
      </Route>
    </Routes>
  );
}
