import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/material.dart';

const base = 'https://barra.cos.ufrj.br/t5/rest';

const fundo = Color(0xFF151A20);
const superficie = Color(0xFF1D242C);
const divisor = Color(0xFF2E3741);
const acento = Color(0xFF3D8BFD);
const texto = Color(0xFFE6EBF0);
const textoFraco = Color(0xFF8B98A8);
const erroCor = Color(0xFFF07167);
const perigo = Color(0xFFC0392B);

const corItem = Color(0xFF222A33);

const altura = 48.0;
const duracao = Duration(milliseconds: 700);
const curva = Curves.easeInOutCubic;
const inclinacao = 0.09;

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lista de Tarefas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: acento,
        scaffoldBackgroundColor: fundo,
        visualDensity: VisualDensity.compact,
      ),
      home: const Login(),
    );
  }
}

class Tarefa {
  final String titulo;
  bool feito;
  bool apagando;

  Tarefa(this.titulo, {this.feito = false, this.apagando = false});
}

class Sessao {
  final String nome;
  final String email;
  final String token;

  Sessao(this.nome, this.email, this.token);
}

class ApiErro implements Exception {
  final int status;
  final String mensagem;

  ApiErro(this.status, this.mensagem);
}

class Resposta {
  final int status;
  final String corpo;

  Resposta(this.status, this.corpo);
}

Map<String, String> cabecalhos([String? token]) => {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

Future<Resposta> requisitar(
  String metodo,
  String url,
  Map<String, String> cabecalho, [
  String? corpo,
]) async {
  final opcoes = JSObject();
  opcoes['method'] = metodo.toJS;

  final campos = JSObject();
  cabecalho.forEach((nome, valor) => campos[nome] = valor.toJS);
  opcoes['headers'] = campos;

  if (corpo != null) opcoes['body'] = corpo.toJS;

  final resposta = await globalContext
      .callMethod<JSPromise<JSObject>>('fetch'.toJS, url.toJS, opcoes)
      .toDart;
  final status = resposta.getProperty<JSNumber>('status'.toJS).toDartInt;
  final texto =
      await resposta.callMethod<JSPromise<JSString>>('text'.toJS).toDart;

  return Resposta(status, texto.toDart);
}

String mensagemDoErro(Resposta r, String padrao) {
  try {
    final dados = jsonDecode(r.corpo);
    if (dados is Map && dados['message'] != null) return '${dados['message']}';
  } catch (_) {}
  return padrao;
}

Future<void> registrar(
  String nome,
  String email,
  String celular,
  String senha,
) async {
  final r = await requisitar(
    'POST',
    '$base/rpc/registra_usuario',
    cabecalhos(),
    jsonEncode({
      'nome': nome,
      'email': email,
      'senha': senha,
      if (celular.isNotEmpty) 'celular': celular,
    }),
  );

  if (r.status != 200) {
    throw ApiErro(r.status, mensagemDoErro(r, 'Não foi possível cadastrar.'));
  }
}

Future<Sessao> logar(String email, String senha) async {
  final r = await requisitar(
    'POST',
    '$base/rpc/fazer_login',
    cabecalhos(),
    jsonEncode({'email': email, 'senha': senha}),
  );

  if (r.status != 200) {
    throw ApiErro(r.status, mensagemDoErro(r, 'Não foi possível entrar.'));
  }

  final dados = jsonDecode(r.corpo);
  return Sessao(
    '${dados['nome'] ?? dados['email']}',
    dados['email'],
    dados['token'],
  );
}

Future<List<Tarefa>?> baixarTarefas(Sessao sessao) async {
  final r = await requisitar(
    'GET',
    '$base/tarefas',
    cabecalhos(sessao.token),
  );

  if (r.status == 401) throw ApiErro(401, 'Sessão expirada.');
  if (r.status != 200) {
    throw ApiErro(r.status, mensagemDoErro(r, 'Falha ao ler a lista.'));
  }

  final registros = jsonDecode(r.corpo) as List;
  if (registros.isEmpty) return null;

  final valor = registros.first['valor'];
  if (valor is! List) return [];

  final bruto = List.from(valor);
  bruto.sort((a, b) => (a['ordem'] ?? 0).compareTo(b['ordem'] ?? 0));

  return bruto
      .map((t) => Tarefa('${t['titulo']}', feito: t['concluida'] == true))
      .toList();
}

Future<bool> criarLista(Sessao sessao, List valor) async {
  final r = await requisitar(
    'POST',
    '$base/tarefas',
    cabecalhos(sessao.token),
    jsonEncode({'email': sessao.email, 'valor': valor}),
  );

  if (r.status == 401) throw ApiErro(401, 'Sessão expirada.');
  if (r.status == 409) return false;
  if (r.status != 201) {
    throw ApiErro(r.status, mensagemDoErro(r, 'Falha ao criar a lista.'));
  }
  return true;
}

Future<bool> salvarLista(Sessao sessao, List valor) async {
  final filtro = 'email=eq.${Uri.encodeQueryComponent(sessao.email)}';
  final r = await requisitar(
    'PATCH',
    '$base/tarefas?$filtro',
    {
      ...cabecalhos(sessao.token),
      'Prefer': 'return=representation',
    },
    jsonEncode({'valor': valor}),
  );

  if (r.status == 401) throw ApiErro(401, 'Sessão expirada.');
  if (r.status != 200) {
    throw ApiErro(r.status, mensagemDoErro(r, 'Falha ao salvar a lista.'));
  }

  final linhas = jsonDecode(r.corpo) as List;
  return linhas.isNotEmpty;
}

InputDecoration decoracao(String rotulo) {
  return InputDecoration(
    labelText: rotulo,
    labelStyle: const TextStyle(color: textoFraco, fontSize: 14),
    errorStyle: const TextStyle(fontSize: 12, color: erroCor),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: divisor),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: acento, width: 1.5),
    ),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide(color: divisor),
    ),
  );
}

Widget botaoCheio(String rotulo, bool ocupado, VoidCallback aoTocar) {
  return SizedBox(
    height: 44,
    child: FilledButton(
      onPressed: ocupado ? null : aoTocar,
      style: FilledButton.styleFrom(
        backgroundColor: acento,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF2B4670),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: ocupado
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              rotulo,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
    ),
  );
}

Widget aviso(String mensagem) {
  return Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 16, color: erroCor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            mensagem,
            style: const TextStyle(color: erroCor, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final email = TextEditingController();
  final senha = TextEditingController();

  bool ocupado = false;
  bool naoCadastrado = false;
  String? erro;

  @override
  void dispose() {
    email.dispose();
    senha.dispose();
    super.dispose();
  }

  void entrar() async {
    if (email.text.trim().isEmpty || senha.text.isEmpty) {
      setState(() => erro = 'Preencha email e senha.');
      return;
    }

    setState(() {
      ocupado = true;
      erro = null;
      naoCadastrado = false;
    });

    try {
      final sessao = await logar(email.text.trim(), senha.text);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => Lista(sessao: sessao)),
      );
    } on ApiErro catch (e) {
      if (!mounted) return;
      setState(() {
        erro = e.mensagem;
        naoCadastrado = e.mensagem.contains('não encontrado');
        ocupado = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        erro = 'Não foi possível falar com o servidor.';
        ocupado = false;
      });
    }
  }

  void abrirCadastro() async {
    final criado = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const Cadastro()),
    );
    if (criado == null || !mounted) return;

    setState(() {
      email.text = criado;
      senha.clear();
      erro = null;
      naoCadastrado = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cadastro concluído. Agora faça o login.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: acento, size: 26),
                    SizedBox(width: 8),
                    Text(
                      'Tarefas',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: texto,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  'Entrar',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: texto,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: email,
                  enabled: !ocupado,
                  style: const TextStyle(fontSize: 15, color: texto),
                  keyboardType: TextInputType.emailAddress,
                  decoration: decoracao('Email'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: senha,
                  enabled: !ocupado,
                  obscureText: true,
                  style: const TextStyle(fontSize: 15, color: texto),
                  onSubmitted: (_) => entrar(),
                  decoration: decoracao('Senha'),
                ),
                if (erro != null) aviso(erro!),
                const SizedBox(height: 22),
                botaoCheio('Entrar', ocupado, entrar),
                const SizedBox(height: 20),
                const Divider(color: divisor, height: 1),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      naoCadastrado
                          ? 'Esse email não tem conta.'
                          : 'Ainda não tem conta?',
                      style: const TextStyle(fontSize: 13, color: textoFraco),
                    ),
                    TextButton(
                      onPressed: ocupado ? null : abrirCadastro,
                      style: TextButton.styleFrom(
                        foregroundColor: acento,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text(
                        'Cadastre-se',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Cadastro extends StatefulWidget {
  const Cadastro({super.key});

  @override
  State<Cadastro> createState() => _CadastroState();
}

class _CadastroState extends State<Cadastro> {
  final formulario = GlobalKey<FormState>();
  final nome = TextEditingController();
  final email = TextEditingController();
  final celular = TextEditingController();
  final senha = TextEditingController();
  final confirmacao = TextEditingController();

  bool ocupado = false;
  String? erro;

  @override
  void dispose() {
    nome.dispose();
    email.dispose();
    celular.dispose();
    senha.dispose();
    confirmacao.dispose();
    super.dispose();
  }

  void cadastrar() async {
    if (!formulario.currentState!.validate()) return;

    setState(() {
      ocupado = true;
      erro = null;
    });

    final digitado = email.text.trim().toLowerCase();

    try {
      await registrar(
        nome.text.trim(),
        digitado,
        celular.text.trim(),
        senha.text,
      );
      if (!mounted) return;
      Navigator.pop(context, digitado);
    } on ApiErro catch (e) {
      if (!mounted) return;
      setState(() {
        erro = e.mensagem;
        ocupado = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        erro = 'Não foi possível falar com o servidor.';
        ocupado = false;
      });
    }
  }

  Widget campo(
    TextEditingController controle,
    String rotulo,
    String? Function(String?) validador, {
    TextInputType? teclado,
    bool secreto = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controle,
        enabled: !ocupado,
        obscureText: secreto,
        keyboardType: teclado,
        validator: validador,
        style: const TextStyle(fontSize: 15, color: texto),
        decoration: decoracao(rotulo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: fundo,
        surfaceTintColor: fundo,
        foregroundColor: texto,
        elevation: 0,
        toolbarHeight: 52,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Form(
              key: formulario,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Criar conta',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: texto,
                    ),
                  ),
                  const SizedBox(height: 20),
                  campo(nome, 'Nome', (v) {
                    if ((v ?? '').trim().length < 3) {
                      return 'Mínimo de 3 caracteres.';
                    }
                    return null;
                  }),
                  campo(email, 'Email', (v) {
                    final digitado = (v ?? '').trim();
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(digitado)) {
                      return 'Email em formato inválido.';
                    }
                    return null;
                  }, teclado: TextInputType.emailAddress),
                  campo(celular, 'Celular (opcional)', (v) {
                    final digitado = (v ?? '').trim();
                    if (digitado.isEmpty) return null;
                    if (digitado.length < 8 || digitado.length > 30) {
                      return 'Entre 8 e 30 caracteres.';
                    }
                    if (!RegExp(r'^[0-9 ()+\-.]+$').hasMatch(digitado)) {
                      return 'Use apenas dígitos, espaços e ( ) + - .';
                    }
                    return null;
                  }, teclado: TextInputType.phone),
                  campo(senha, 'Senha', (v) {
                    if ((v ?? '').length < 8) return 'Mínimo de 8 caracteres.';
                    return null;
                  }, secreto: true),
                  campo(confirmacao, 'Confirmar senha', (v) {
                    if (v != senha.text) return 'As senhas não conferem.';
                    return null;
                  }, secreto: true),
                  if (erro != null) aviso(erro!),
                  const SizedBox(height: 10),
                  botaoCheio('Cadastrar', ocupado, cadastrar),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: ocupado ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: textoFraco),
                    child: const Text(
                      'Voltar ao login',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Lista extends StatefulWidget {
  final Sessao sessao;

  const Lista({super.key, required this.sessao});

  @override
  State<Lista> createState() => _ListaState();
}

class _ListaState extends State<Lista> {
  final campo = TextEditingController();
  final cursor = FocusNode();
  final itens = <Tarefa>[];
  final apagando = <String, Timer>{};
  final rolagem = ScrollController();
  final chaveLista = GlobalKey<AnimatedListState>();

  bool carregando = true;
  bool temLista = false;
  bool saiu = false;
  String status = 'carregando...';
  String? alerta;

  Tarefa? voando;
  double origem = 0;
  bool decolou = false;
  int voo = 0;
  Timer? pouso;

  int get pendentes => itens.where((t) => !t.feito).length;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  @override
  void dispose() {
    for (final timer in apagando.values) {
      timer.cancel();
    }
    apagando.clear();
    pouso?.cancel();
    rolagem.dispose();
    campo.dispose();
    cursor.dispose();
    super.dispose();
  }

  void carregar() async {
    pouso?.cancel();
    setState(() {
      carregando = true;
      voando = null;
      status = 'carregando...';
    });

    try {
      final baixadas = await baixarTarefas(widget.sessao);
      if (!mounted) return;

      setState(() {
        itens
          ..clear()
          ..addAll(baixadas ?? []);
        reordenar();
        temLista = baixadas != null;
        carregando = false;
        status = temLista ? 'sincronizado' : 'criando a lista...';
      });

      if (!temLista) salvar();
    } on ApiErro catch (e) {
      if (!mounted) return;
      if (e.status == 401) {
        expirou();
        return;
      }
      setState(() {
        carregando = false;
        status = e.mensagem;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        carregando = false;
        status = 'sem conexão com o servidor';
      });
    }
  }

  void salvar() async {
    if (saiu) return;

    final valor = [
      for (var i = 0; i < itens.length; i++)
        {'titulo': itens[i].titulo, 'concluida': itens[i].feito, 'ordem': i}
    ];

    setState(() => status = 'salvando...');

    try {
      if (temLista) {
        final alterou = await salvarLista(widget.sessao, valor);
        if (!alterou) await criarLista(widget.sessao, valor);
      } else {
        final criou = await criarLista(widget.sessao, valor);
        if (!criou) await salvarLista(widget.sessao, valor);
        temLista = true;
      }
      if (!mounted) return;
      setState(() => status = 'sincronizado');
    } on ApiErro catch (e) {
      if (!mounted) return;
      if (e.status == 401) {
        expirou();
        return;
      }
      setState(() => status = e.mensagem);
    } catch (_) {
      if (!mounted) return;
      setState(() => status = 'sem conexão com o servidor');
    }
  }

  void expirou() async {
    if (saiu) return;
    saiu = true;

    for (final timer in apagando.values) {
      timer.cancel();
    }
    apagando.clear();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogo) => AlertDialog(
        backgroundColor: superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Text(
          'Sessão expirada',
          style: TextStyle(color: texto, fontSize: 17),
        ),
        content: const Text(
          'O token vale 5 minutos e já venceu. Entre de novo para continuar.',
          style: TextStyle(color: textoFraco, fontSize: 14),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogo),
            style: FilledButton.styleFrom(
              backgroundColor: acento,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Voltar ao login'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    voltarAoLogin();
  }

  void voltarAoLogin() {
    saiu = true;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
      (rota) => false,
    );
  }

  void reordenar() {
    final naoFeitas = itens.where((t) => !t.feito).toList();
    final feitas = itens.where((t) => t.feito).toList();
    itens
      ..clear()
      ..addAll(naoFeitas)
      ..addAll(feitas);
  }

  void incluir() {
    final titulo = campo.text.trim();

    if (titulo.isEmpty) {
      setState(() => alerta = 'Informe uma descrição.');
      return;
    }
    if (itens.any((t) => t.titulo == titulo)) {
      setState(() => alerta = 'Essa tarefa já consta na lista.');
      return;
    }

    final posicao = pendentes;
    setState(() {
      itens.insert(posicao, Tarefa(titulo));
      alerta = null;
      campo.clear();
    });
    chaveLista.currentState?.insertItem(posicao, duration: Duration.zero);
    cursor.requestFocus();
    salvar();
  }

  void marcar(Tarefa item) {
    if (item.feito) {
      desconcluir(item);
    } else {
      concluir(item);
    }
  }

  void concluir(Tarefa item) {
    final de = itens.indexWhere((t) => t.titulo == item.titulo);
    if (de < 0) return;

    final lista = chaveLista.currentState;
    pouso?.cancel();

    setState(() {
      itens.removeAt(de);
      item.feito = true;
      final para = pendentes;
      itens.insert(para, item);

      voando = item;
      origem = de * altura;
      decolou = false;
      voo++;

      lista?.removeItem(
        de,
        (context, animacao) => lacuna(animacao),
        duration: duracao,
      );
      lista?.insertItem(para, duration: duracao);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => decolou = true);
    });

    pouso = Timer(duracao + const Duration(milliseconds: 50), () {
      if (mounted) setState(() => voando = null);
    });

    salvar();
  }

  void desconcluir(Tarefa item) {
    final de = itens.indexWhere((t) => t.titulo == item.titulo);
    if (de < 0) return;

    final lista = chaveLista.currentState;

    setState(() {
      itens.removeAt(de);
      item.feito = false;
      final para = pendentes;
      itens.insert(para, item);

      lista?.removeItem(
        de,
        (context, animacao) => const SizedBox.shrink(),
        duration: Duration.zero,
      );
      lista?.insertItem(para, duration: Duration.zero);
    });

    salvar();
  }

  void apagar(Tarefa item) {
    if (item.apagando) return;

    setState(() => item.apagando = true);

    apagando[item.titulo] = Timer(const Duration(seconds: 3), () {
      apagando.remove(item.titulo);
      if (!mounted) return;

      final i = itens.indexWhere((t) => t.titulo == item.titulo);
      if (i < 0) return;

      setState(() {
        itens.removeAt(i);
        if (voando?.titulo == item.titulo) voando = null;
      });
      chaveLista.currentState?.removeItem(
        i,
        (context, animacao) => const SizedBox.shrink(),
        duration: Duration.zero,
      );
      salvar();
    });
  }

  void desfazer(Tarefa item) {
    apagando.remove(item.titulo)?.cancel();
    setState(() => item.apagando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  topo(),
                  const SizedBox(height: 18),
                  entrada(),
                  const SizedBox(height: 16),
                  Expanded(child: moldura()),
                  const SizedBox(height: 10),
                  rodape(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget topo() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Minhas tarefas',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: texto,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: superficie,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$pendentes',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textoFraco,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                widget.sessao.nome,
                style: const TextStyle(fontSize: 12, color: textoFraco),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Recarregar',
          onPressed: carregando ? null : carregar,
          icon: const Icon(Icons.refresh, size: 19, color: textoFraco),
        ),
        IconButton(
          tooltip: 'Sair',
          onPressed: voltarAoLogin,
          icon: const Icon(Icons.logout, size: 18, color: textoFraco),
        ),
      ],
    );
  }

  Widget entrada() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.add, color: acento, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: campo,
                focusNode: cursor,
                enabled: !carregando,
                style: const TextStyle(fontSize: 15, color: texto),
                onSubmitted: (_) => incluir(),
                decoration: const InputDecoration(
                  hintText: 'Adicionar tarefa',
                  hintStyle: TextStyle(color: textoFraco, fontSize: 15),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            TextButton(
              onPressed: carregando ? null : incluir,
              style: TextButton.styleFrom(
                foregroundColor: acento,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text(
                'Incluir',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const Divider(color: divisor, height: 1),
        if (alerta != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 34),
            child: Text(
              alerta!,
              style: const TextStyle(color: erroCor, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget moldura() {
    Widget dentro;

    if (carregando) {
      dentro = const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(color: acento, strokeWidth: 2.5),
        ),
      );
    } else {
      dentro = Stack(
        fit: StackFit.expand,
        children: [
          AnimatedList(
            key: chaveLista,
            controller: rolagem,
            padding: EdgeInsets.zero,
            initialItemCount: itens.length,
            itemBuilder: (context, i, animacao) =>
                itemAnimado(itens[i], animacao),
          ),
          if (itens.isEmpty)
            const Center(
              child: Icon(Icons.task_alt, size: 40, color: divisor),
            ),
          if (voando != null) fantasma(voando!),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: superficie,
        border: Border.all(color: divisor),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: dentro,
    );
  }

  Widget itemAnimado(Tarefa item, Animation<double> animacao) {
    final escondido = voando?.titulo == item.titulo;

    return SizeTransition(
      sizeFactor: animacao.drive(CurveTween(curve: curva)),
      child: IgnorePointer(
        ignoring: escondido,
        child: Opacity(
          opacity: escondido ? 0 : 1,
          child: linha(item),
        ),
      ),
    );
  }

  Widget lacuna(Animation<double> animacao) {
    return SizeTransition(
      sizeFactor: animacao.drive(CurveTween(curve: curva)),
      child: Container(height: altura, color: corItem),
    );
  }

  Widget fantasma(Tarefa item) {
    final deslocamento = rolagem.hasClients ? rolagem.offset : 0.0;
    final destino = itens.indexWhere((t) => t.titulo == item.titulo) * altura;

    return AnimatedPositioned(
      key: ValueKey(voo),
      duration: duracao,
      curve: curva,
      left: 0,
      right: 0,
      height: altura,
      top: (decolou ? destino : origem) - deslocamento,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: duracao,
          builder: (context, t, filho) => Transform.rotate(
            angle: math.sin(math.pi * t) * inclinacao,
            child: filho,
          ),
          child: Material(
            elevation: 8,
            color: corItem,
            shadowColor: Colors.black,
            surfaceTintColor: Colors.transparent,
            child: conteudo(item),
          ),
        ),
      ),
    );
  }

  Widget linha(Tarefa item) {
    return Dismissible(
      key: ValueKey(item.titulo),
      background:
          faixa(const Color(0xFF2F7D4F), Icons.check, Alignment.centerLeft),
      secondaryBackground:
          faixa(perigo, Icons.delete_outline, Alignment.centerRight),
      confirmDismiss: (sentido) async {
        if (sentido == DismissDirection.startToEnd) {
          marcar(item);
        } else {
          apagar(item);
        }
        return false;
      },
      child: conteudo(item),
    );
  }

  Widget conteudo(Tarefa item) {
    final cor = item.apagando ? const Color(0xFF4A2220) : corItem;
    final tinta = item.feito ? textoFraco : texto;

    return Container(
      height: altura,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: cor,
        border: const Border(bottom: BorderSide(color: divisor)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: item.feito,
              onChanged: (_) => marcar(item),
              shape: const CircleBorder(),
              activeColor: textoFraco,
              checkColor: fundo,
              side: BorderSide(
                color: item.apagando ? Colors.white54 : acento,
                width: 1.6,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              item.titulo,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                color: item.apagando ? Colors.white : tinta,
                decorationColor: item.apagando ? Colors.white : tinta,
                decoration: item.feito
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (item.apagando)
            TextButton(
              onPressed: () => desfazer(item),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 30),
              ),
              child: const Text(
                'Desfazer',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            )
          else
            IconButton(
              onPressed: () => apagar(item),
              icon: const Icon(Icons.close, size: 16),
              color: textoFraco,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            ),
        ],
      ),
    );
  }

  Widget faixa(Color cor, IconData simbolo, Alignment lado) {
    return Container(
      color: cor,
      alignment: lado,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(simbolo, size: 19, color: Colors.white),
    );
  }

  Widget rodape() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$pendentes pendente(s) · ${itens.length - pendentes} concluída(s)',
          style: const TextStyle(fontSize: 12, color: textoFraco),
        ),
        Flexible(
          child: Text(
            status,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: textoFraco),
          ),
        ),
      ],
    );
  }
}
