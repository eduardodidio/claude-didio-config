# Reunião cliente Petshop — 2026-05-07

Reunião de descoberta com a equipe operacional. O cliente quer um
sistema interno para gerenciar agendamentos de pets.

## Telas necessárias

- Lista de agendamentos do dia (mostrar pet, dono, horário, status).
- Detalhe de um agendamento (todos os campos + observações).
- Cadastro de novo agendamento (formulário simples).

## Entidades mencionadas

- Agendamento: id, pet_nome, dono_nome, horario, status (confirmado/pendente/cancelado), observacoes.
- Pet: id, nome, especie, raca, dono_nome.

## Regras

- Status é só visual (sem workflow real ainda).
- Login não é prioridade; deixar tela aberta.
- Ordenação da lista por horário crescente.

## Próximos passos

Revisar o POC gerado com a equipe operacional na próxima semana.
