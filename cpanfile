requires 'Future', '0.50';
requires 'Future::Utils', '0.50';
requires 'IO::Async', '0.802';
requires 'Net::Async::HTTP', '0.49';
requires 'WWW::Firecrawl', '0.001';
requires 'WWW::Firecrawl::Error', '0.001';

on test => sub {
  requires 'HTTP::Response';
  requires 'JSON::MaybeXS';
  requires 'Test::Fatal', '0.014';
  requires 'Test::LoadAllModules', '0.021';
  requires 'Test::More', '0.98';
};
